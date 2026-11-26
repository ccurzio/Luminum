<?php
//
// File repository chunked upload endpoint (docs/p2p.md, Phase 0, the
// HTTP ingestion vector). A single multipart POST cannot carry GB-scale
// files (PHP post_max_size / nginx client_max_body_size), so the upload
// is chunked: the client (the console package UI, a later phase) splits
// the file into raw binary chunks and POSTs them one at a time.
//
// Actions (POST only, ?action=...):
//
//   init    JSON { "name": "...", "size": <bytes> }
//           Opens an upload session: a UUID, a CONTENT.UPLOADS row, and a
//           hidden temp file content/staging/http/.up-{id}.part.
//
//   chunk   raw binary body, ?id={uuid}
//           Appends the body to the temp file and advances RECEIVED.
//           Rejects chunks that would push RECEIVED past the declared
//           SIZE.
//
//   finish  JSON { "id": "{uuid}" }
//           Requires RECEIVED == SIZE, renames the temp file into the
//           staging directory as {id}-{name}, and marks the session
//           DONE. The broker's discovery scan (60 s) then hashes,
//           dedupes, and registers the file in CONTENT.FILES exactly
//           like an NFS/SMB drop - one ingestion code path for all
//           vectors.
//
// Role gate: ROLE <= 2 (the same gate as package creation in
// admin/packages.php). The REPOHTTP vector must be Enabled in
// SYSTEM.CONFIG (checked at init; an in-flight upload may still finish
// if the vector is disabled mid-upload).
//
require_once __DIR__ . '/_init.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
	json_error('Method not allowed', 405);
}

// CSRF gate: the console JS sends the session's token in the X-CSRF-Token
// header (read from the page's <meta name="csrf-token"> tag); a POST
// without it is a forged cross-site submission.
if (!luminum_csrf_valid()) {
	json_error('Invalid or missing CSRF token', 403);
}

// Role gate: uploading repository content is a content-management action
// (ROLE <= 2, matching package creation).
$result = api_query($db, "select u.ROLE from USERS u join SESSION s on s.ID = u.ID where s.SID = '$sid' and u.ENABLED = 1");
$role = mysqli_fetch_assoc($result);
if ($role === null || (int)$role['ROLE'] > 2) {
	json_error('Insufficient role for repository uploads', 403);
}

// The content root is the install root's content/ directory (the console
// serves from <install root>/console/html). LUMINUM_CONTENT_ROOT overrides
// it for tests.
$contentRoot = getenv('LUMINUM_CONTENT_ROOT');
if ($contentRoot === false || $contentRoot === '') {
	$contentRoot = __DIR__ . '/../../../content';
}
$staging = "$contentRoot/staging/http";

// The HTTP vector must be enabled (SYSTEM.CONFIG REPOHTTP, read live).
$result = api_query($db, "select CVAL from CONFIG where CKEY = 'REPOHTTP'", 'SYSTEM');
$cfg = mysqli_fetch_assoc($result);
if ($cfg === null || strtolower($cfg['CVAL']) !== 'enabled') {
	json_error('The HTTP repository vector is disabled', 403);
}

// UUIDv4 from random_bytes (no extension dependency).
function upload_uuid() {
	$b = random_bytes(16);
	$b[6] = chr((ord($b[6]) & 0x0f) | 0x40);
	$b[8] = chr((ord($b[8]) & 0x3f) | 0x80);
	$h = bin2hex($b);
	return substr($h, 0, 8) . '-' . substr($h, 8, 4) . '-' . substr($h, 12, 4) . '-' . substr($h, 16, 4) . '-' . substr($h, 20, 12);
}

// A valid session ID is a lowercase UUIDv4 as returned by init.
function upload_valid_id($id) {
	return is_string($id) && preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/', $id) === 1;
}

$action = $_GET['action'] ?? '';

if ($action === 'init') {
	$body = json_decode(file_get_contents('php://input'), true);
	if (!is_array($body)) {
		json_error('Invalid JSON body', 400);
	}
	// The name is the file's original name: no path components (the
	// repository is flat), no leading dot (the discovery scan skips
	// hidden entries), at most 255 characters (filesystem limit).
	$name = is_string($body['name'] ?? null) ? $body['name'] : '';
	$name = str_replace('\\', '/', $name);
	$name = basename($name);
	if ($name === '' || $name === '.' || $name === '/' || $name[0] === '.' || strlen($name) > 255 || strpos($name, "\0") !== false) {
		json_error('Invalid file name', 400);
	}
	$size = $body['size'] ?? null;
	if (!is_numeric($size) || (int)$size < 1 || (int)$size > 10 * 1024 * 1024 * 1024) {
		json_error('Invalid file size (1 byte - 10 GB)', 400);
	}
	$size = (int)$size;

	if (!is_dir($staging)) {
		if (!mkdir($staging, 0750, true)) {
			json_error('Unable to create the repository staging directory', 500);
		}
	}

	$id = upload_uuid();
	$tmp = "$staging/.up-$id.part";
	$fh = fopen($tmp, 'xb');
	if ($fh === false) {
		json_error('Unable to create the upload temp file', 500);
	}
	fclose($fh);
	chmod($tmp, 0600);

	$name = mysqli_real_escape_string($db, $name);
	api_query($db, "insert into UPLOADS (ID,NAME,SIZE,RECEIVED,VIA,CREATED) values ('$id','$name',$size,0,'http',now())", 'CONTENT');
	json_out(['ok' => true, 'id' => $id, 'received' => 0]);
}

if ($action === 'chunk') {
	$id = $_GET['id'] ?? '';
	if (!upload_valid_id($id)) {
		json_error('Invalid upload ID', 400);
	}
	$result = api_query($db, "select ID,SIZE,RECEIVED,DONE from UPLOADS where ID = '$id'", 'CONTENT');
	$up = mysqli_fetch_assoc($result);
	if ($up === null) {
		json_error('No such upload', 404);
	}
	if ($up['DONE'] !== null) {
		json_error('Upload already finished', 400);
	}
	$tmp = "$staging/.up-$id.part";
	if (!is_file($tmp)) {
		json_error('Upload temp file missing', 404);
	}
	$chunk = file_get_contents('php://input');
	$bytes = strlen($chunk);
	if ($bytes < 1) {
		json_error('Empty chunk', 400);
	}
	if ((int)$up['RECEIVED'] + $bytes > (int)$up['SIZE']) {
		json_error('Chunk exceeds the declared file size', 400);
	}
	if (file_put_contents($tmp, $chunk, FILE_APPEND | LOCK_EX) === false) {
		json_error('Unable to append the chunk', 500);
	}
	$received = (int)$up['RECEIVED'] + $bytes;
	api_query($db, "update UPLOADS set RECEIVED = $received where ID = '$id'", 'CONTENT');
	json_out(['ok' => true, 'received' => $received]);
}

if ($action === 'finish') {
	$body = json_decode(file_get_contents('php://input'), true);
	$id = is_array($body) && is_string($body['id'] ?? null) ? $body['id'] : '';
	if (!upload_valid_id($id)) {
		json_error('Invalid upload ID', 400);
	}
	$result = api_query($db, "select ID,NAME,SIZE,RECEIVED,DONE from UPLOADS where ID = '$id'", 'CONTENT');
	$up = mysqli_fetch_assoc($result);
	if ($up === null) {
		json_error('No such upload', 404);
	}
	if ($up['DONE'] !== null) {
		json_out(['ok' => true, 'finished' => false]);
	}
	if ((int)$up['RECEIVED'] !== (int)$up['SIZE']) {
		json_error('Upload incomplete: ' . $up['RECEIVED'] . ' of ' . $up['SIZE'] . ' bytes received', 400);
	}
	$tmp = "$staging/.up-$id.part";
	// Staged as {id}-{name}: the uuid prefix keeps concurrent same-name
	// uploads from colliding in staging; the discovery scan resolves the
	// original name from this row (Luminum::Repo::scan_vector).
	$final = "$staging/$id-" . $up['NAME'];
	if (!is_file($tmp)) {
		json_error('Upload temp file missing', 404);
	}
	if (file_exists($final) || !rename($tmp, $final)) {
		json_error('Unable to stage the completed upload', 500);
	}
	api_query($db, "update UPLOADS set DONE = now() where ID = '$id'", 'CONTENT');
	json_out(['ok' => true, 'finished' => true]);
}

json_error('Unknown action', 400);
