#
# Luminum::Repo - the server file repository (docs/p2p.md, Phase 0).
#
# The repository is the server's content-addressed file store: every file
# that can be attached to a package (and later distributed, server-seeded
# or P2P) lives here, named by its SHA-256. Files arrive through ingestion
# vectors - HTTP (chunked console upload, the default) or NFS/SMB (the
# operator copies files into the exported staging area) - and all vectors
# converge on one discovery path: per-vector staging directories plus a
# periodic scan that hashes, dedupes, and registers dropped files in
# CONTENT.FILES.
#
# A file is cataloged, not authorized: it becomes distributable only when
# an administrator attaches it to a package (PKGFILES), which is the
# authorization gate for P2P distribution.
#

package Luminum::Repo;

use strict;
use warnings;
use Digest::SHA;
use File::Path qw(make_path);
use File::Basename qw(dirname);

# Vectors, in scan order. The vector name is the staging subdirectory name
# and the CONTENT.FILES.VIA value (VIA, not VECTOR: MariaDB 11.7+ reserves
# that word for the vector data type).
our @VECTORS = qw(http nfs smb);

# A dropped file is only considered complete when its mtime is at least
# this many seconds old: an in-flight NFS/SMB copy keeps a fresh mtime and
# is picked up on a later tick. HTTP uploads are renamed into staging only
# when the client has sent every chunk, so the rule is harmless for them.
our $STABLE_SECS = 10;

# Upload sessions not finished within this window are swept (row + temp
# file), as are orphan temp files whose row is gone.
our $UPLOAD_STALE_SECS = 86400;

# Layout -----------------------------------------------------------------

sub staging_dir {
	my ($root, $vector) = @_;
	return "$root/staging/$vector";
}

# Content-addressed store path: the first two hash bytes as subdirectories
# (65536 buckets keeps any single directory small at fleet scale).
sub store_path {
	my ($root, $sha) = @_;
	return "$root/files/" . substr($sha, 0, 2) . "/" . substr($sha, 2, 2) . "/$sha";
}

# Create the repository layout (idempotent): content/files plus one
# staging directory per vector. Directories are 0750 - repository content
# is not world-readable. make_path returns only the directories it
# created, so an all-present layout comes back as an empty list; the
# error list (File::Path 2.18 fills the error variable with an arrayref)
# is the failure signal.
sub bootstrap {
	my ($root) = @_;
	return 0 unless defined $root && length $root;
	my $err = [];
	make_path("$root/files", { mode => 0750, error => \$err });
	return 0 if @$err;
	for my $v (@VECTORS) {
		make_path(staging_dir($root, $v), { mode => 0750, error => \$err });
		return 0 if @$err;
	}
	return 1;
}

# Hashing ----------------------------------------------------------------

# Streaming SHA-256 of a file (1 MiB reads; a 1 GB file never sits in
# memory). Returns the lowercase hex digest, or undef when the file cannot
# be read.
sub sha256_file {
	my ($path) = @_;
	open(my $fh, '<:raw', $path) or return undef;
	my $ctx = Digest::SHA->new(256);
	my $buf;
	$ctx->add($buf) while read($fh, $buf, 1024 * 1024);
	close($fh);
	return $ctx->hexdigest;
}

# Configuration ----------------------------------------------------------

# The enabled ingestion vectors, read live from SYSTEM.CONFIG (REPOHTTP /
# REPONFS / REPOSMB, Enabled/Disabled) so an admin change takes effect on
# the next scan without a broker restart. A missing key falls back to the
# installer default (http enabled, nfs/smb disabled).
sub enabled_vectors {
	my ($sysdbh) = @_;
	my %def = ( REPOHTTP => 1, REPONFS => 0, REPOSMB => 0 );
	my @on;
	for my $v (@VECTORS) {
		my $key = "REPO" . uc($v);
		my $on = $def{$key};
		my @row = eval { $sysdbh->selectrow_array("select CVAL from CONFIG where CKEY = ?", undef, $key) };
		$on = (defined $row[0] && lc($row[0]) eq "enabled") ? 1 : 0 if @row && !$@;
		push @on, $v if $on;
	}
	return @on;
}

# Registration -----------------------------------------------------------

# Register one complete file into the repository: hash it, dedupe against
# CONTENT.FILES, record the catalog row, and move it into the
# content-addressed store. Returns ($files_id, $how) where $how is
# "registered" or "duplicate", or (undef, $reason) on failure. The source
# path is removed either way (moved into the store, or deleted as a
# duplicate of an existing blob).
sub register {
	my ($contentdbh, $root, $path, $name, $vector) = @_;
	my $sha = sha256_file($path) or return (undef, "unable to hash $path");
	my $size = -s $path;
	return (undef, "unable to stat $path") unless defined $size;

	my @dup = $contentdbh->selectrow_array("select ID from FILES where SHA256 = ?", undef, $sha);
	if (@dup) {
		unlink($path);
		return ($dup[0], "duplicate");
	}

	my $dest = store_path($root, $sha);
	make_path(dirname($dest), { mode => 0750 });
	unless (rename($path, $dest)) {
		# rename(2) fails across devices; the repository and staging share
		# one filesystem in practice, but fall back to copy+unlink so a
		# split layout cannot wedge ingestion.
		require File::Copy;
		unless (File::Copy::copy($path, $dest)) {
			unlink($path);
			return (undef, "unable to move into store: $!");
		}
		unlink($path);
	}
	chmod(0640, $dest);

	unless ($contentdbh->do("insert into FILES (SHA256,SIZE,NAME,VIA,STAGED) values (?,?,?,?,now())",
		undef, $sha, $size, $name, $vector)) {
		unlink($dest);
		return (undef, "FILES insert failed: " . $contentdbh->errstr);
	}
	# The SHA256 is unique, so the row can be read back deterministically
	# (no driver-specific last_insert_id).
	my @row = $contentdbh->selectrow_array("select ID from FILES where SHA256 = ?", undef, $sha);
	return (undef, "FILES row missing after insert") unless @row;
	return ($row[0], "registered");
}

# Discovery scan ---------------------------------------------------------

# Scan one vector's staging directory: register every stable, complete
# file. Hidden entries (dotfiles) are skipped - in-flight HTTP upload temp
# files (.up-{id}.part) are hidden until the finish action renames them.
# Returns a list of human-readable results for the log.
sub scan_vector {
	my ($contentdbh, $root, $vector, $log) = @_;
	my $dir = staging_dir($root, $vector);
	return () unless -d $dir;
	opendir(my $dh, $dir) or do { $log->("repo: cannot open $dir: $!") if $log; return (); };
	my @out;
	for my $entry (sort readdir($dh)) {
		next if $entry =~ /^\./;
		my $path = "$dir/$entry";
		next unless -f $path;
		my @st = stat($path);
		next unless @st;
		my $age = time() - $st[9];
		if ($age < $STABLE_SECS) {
			push @out, "skip $entry (mtime ${age}s old; copy may still be in flight)";
			next;
		}
		# Finished HTTP uploads are staged as {uuid}-{name} (the prefix
		# keeps concurrent same-name uploads from colliding); the catalog
		# keeps the original name from the UPLOADS row.
		my $name = $entry;
		if ($entry =~ /^([0-9a-f-]{36})-(.+)$/) {
			my @row = $contentdbh->selectrow_array("select NAME from UPLOADS where ID = ? and DONE is not null", undef, $1);
			$name = $row[0] if @row && defined $row[0] && length $row[0];
		}
		my ($id, $how) = register($contentdbh, $root, $path, $name, $vector);
		if (!defined $id) {
			push @out, "FAIL $entry: $how";
		}
		elsif ($how eq "duplicate") {
			push @out, "duplicate $entry (blob already in repository as FILES $id)";
		}
		else {
			push @out, "registered $entry as FILES $id ($how)";
		}
	}
	closedir($dh);
	return @out;
}

# Sweep abandoned chunked uploads: UPLOADS rows not DONE and older than
# $UPLOAD_STALE_SECS are deleted along with their staging temp file, and
# orphan temp files (row gone, e.g. database reset) are deleted outright.
sub sweep_uploads {
	my ($contentdbh, $root, $log) = @_;
	my $cutoff = time() - $UPLOAD_STALE_SECS;
	my $stale = $contentdbh->prepare("select ID,VIA from UPLOADS where DONE is null and CREATED < from_unixtime(?)");
	$stale->execute($cutoff);
	while (my ($id, $vector) = $stale->fetchrow_array()) {
		my $tmp = "$root/staging/$vector/.up-$id.part";
		unlink($tmp) if -e $tmp;
		$contentdbh->do("delete from UPLOADS where ID = ?", undef, $id);
		$log->("repo: swept stale upload $id") if $log;
	}
	for my $v (@VECTORS) {
		my $dir = staging_dir($root, $v);
		next unless -d $dir;
		opendir(my $dh, $dir) or next;
		for my $e (readdir($dh)) {
			next unless $e =~ /^\.up-([0-9a-f-]{36})\.part$/;
			my @row = $contentdbh->selectrow_array("select 1 from UPLOADS where ID = ?", undef, $1);
			unlink("$dir/$e") unless @row;
		}
		closedir($dh);
	}
	return 1;
}

# The broker's periodic entry point (60 s tick): bootstrap the layout,
# scan every enabled vector, and sweep stale uploads. $a{contentdbh} and
# $a{sysdbh} are live DBI handles (CONTENT and SYSTEM); $a{root} is the
# content root (<install root>/content); $a{log} is a coderef.
sub scan {
	my (%a) = @_;
	my $log = $a{log} || sub { };
	my $root = $a{root};
	my $contentdbh = $a{contentdbh};
	my $sysdbh = $a{sysdbh};
	return unless $root && $contentdbh && $sysdbh;

	unless (bootstrap($root)) {
		$log->("repo: unable to create repository layout under $root");
		return;
	}
	sweep_uploads($contentdbh, $root, $log);
	my @vectors = eval { enabled_vectors($sysdbh) };
	if ($@) {
		$log->("repo: cannot read vector configuration: $@");
		return;
	}
	for my $v (@vectors) {
		for my $result (scan_vector($contentdbh, $root, $v, $log)) {
			$log->("repo[$v]: $result");
		}
	}
	return 1;
}

1;
