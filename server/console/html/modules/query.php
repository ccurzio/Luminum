<?php
//
// Query builder. The markup is the builder UI; the PHP below loads the
// sensor catalog (every sensor in CONTENT.SENSORS, with its declared
// parameter fields) so the builder can offer sensor dropdowns and a value
// input per parameter. Submitting posts the built query statement to
// /api/commands.php (protocol 7.3): it is broadcast to all endpoints, and
// only the endpoints on which the conditions evaluate true answer.
//
mysqli_select_db($db, "CONTENT") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
$sq = mysqli_query($db, "select ID,NAME,WITHPARAMS from SENSORS order by NAME");
$sensorlist = [];
while ($srow = mysqli_fetch_assoc($sq)) {
	$sensorlist[] = ['id' => (int)$srow['ID'], 'name' => $srow['NAME'], 'withparams' => (int)$srow['WITHPARAMS'], 'params' => []];
}
$byid = [];
foreach ($sensorlist as $i => $s) { $byid[$s['id']] = $i; }
if (count($sensorlist) > 0) {
	$ids = implode(',', array_map('intval', array_column($sensorlist, 'id')));
	$pq = mysqli_query($db, "select SID,FIELD,DEFAULTVAL from SENSORPARAMS where SID in ($ids)");
	while ($prow = mysqli_fetch_assoc($pq)) {
		$idx = isset($byid[(int)$prow['SID']]) ? $byid[(int)$prow['SID']] : null;
		if ($idx === null) { continue; }
		if (!is_string($prow['FIELD']) || $prow['FIELD'] === '') { continue; }
		$dup = false;
		foreach ($sensorlist[$idx]['params'] as $p) {
			if ($p['field'] === $prow['FIELD']) { $dup = true; break; }
		}
		if ($dup) { continue; }
		$sensorlist[$idx]['params'][] = ['field' => $prow['FIELD'], 'default' => is_string($prow['DEFAULTVAL']) ? $prow['DEFAULTVAL'] : ''];
	}
}
// The catalog for the builder's JS (parameter inputs, submit validation).
$sensorjson = json_encode($sensorlist, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);

// The <option> list shared by every sensor dropdown in the builder's
// initial markup (retrieve rows and condition rows); cloned rows inherit it.
$sensoroptions = "<option value=\"\">(select a sensor)</option>\n";
foreach ($sensorlist as $s) {
	$sensoroptions .= "<option value=\"" . $s['id'] . "\">" . htmlspecialchars($s['name'], ENT_QUOTES) . "</option>\n";
}
?>

<div class="content">
	<h1>Luminum Query</h1>

<div>
	<!-- <div class="module-content" style="display: flex; justify-content: space-between; align-items: flex-start;"> -->
	<div class="module-content" style="padding: 0;">
		<div class="tabbar tabbarback">
			<button type="button" class="tabbaritem tabbutton tablink tabbarsel" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Builder')">Query Builder</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Saved')">Saved Queries</button>
		</div>
		<!-- <div class="main-content"> -->
		<div id="Builder" class="configtab">
			<div style="margin: 20px;">
				<p>
				<span style="font-size: 20px; font-weight: bold; color: #444;">I want to retrieve:</span>
				</p>
				<div id="get-list">
					<div class="list-item" style="margin-bottom: 5px;"><img src="/icons/reorder-dis.png" class="drag-handle" style="vertical-align: middle"> <select class="sensor-select" style="font-size: 15px; height: 30px; width: 220px; margin-left: 2px;"><?php print $sensoroptions ?></select> <span class="param-fields"></span> <img src="/icons/add.png" class="add" style="vertical-align: middle; margin-bottom: 3px;"></div>
				</div>

				<p style="margin-top: 20px;">
				<span style="font-size: 20px; font-weight: bold; color: #444;">From</span> <select style="font-size: 15px; height: 30px; margin-left: 2px; margin-right: 2px;" name="targets" id="targets" class="target-dropdown" onchange="selectSuffix();"><option name="matching" value="matching" default="default">endpoints matching</option><option name="all" value="all">all endpoints</select> <span id="tsuffix" style="font-size: 20px; font-weight: bold; color: #444;"> the following condition:</span>
				</p>
				<div id="from-list">
					<div class="list-item"><img src="/icons/reorder-dis.png" class="drag-handle" style="vertical-align: middle;"> <select class="sensor-select" style="font-size: 15px; height: 30px; width: 220px; margin-left: 2px;"><?php print $sensoroptions ?></select> <select class="row-dropdown" style="font-size: 15px; height: 30px; margin-left: 5px; margin-right: 10px;" name="fromop"><option name="equals" value="equals">==</option><option name="notequals" value="notequals">!=</option><option name="contains" value="contains">=~</option><option name="notcontains" value="notcontains">!~</option><option name="greaterthan" value="greaterthan">&gt;</option><option name="greaterthan" value="greaterorequal">&gt;=</option><option name="lessthan" value="lessthan">&lt;</option><option name="greaterthan" value="lessorequal">&lt;=</option></select><input type="text" class="cond-value" placeholder="Value" maxlength="1024"> <img src="/icons/add.png" class="add" style="vertical-align: middle; margin-bottom: 3px;"></div>
				</div>
			</div>
		</div>
		<div id="Saved" class="configtab" style="display: none;">
			<div style="margin: 20px; text-align: center; font-style: italic; color: #777;">No saved queries yet.</div>
		</div>
	</div>
	<div style="width: 100%; text-align: right; padding-top: 10px;">
		<button id="resetform" class="formgo" style="margin-right: 0;">Reset Form</button> <button id="querygo" class="formgo" style="margin-left: 0;" disabled="disabled" onclick="submitQuery()">Submit Query</button>
	</div>

</div>

<script src="/layout/Sortable.min.js"></script>

<script>
// --- query builder wiring ---------------------------------------------------
// The builder posts a query statement to /api/commands.php (protocol 7.3):
// the retrieve sensors plus the condition tree, broadcast to all endpoints;
// only the endpoints on which the conditions evaluate true answer.

const sensorCatalog = <?php print $sensorjson; ?>;

// The builder's operator dropdown values -> the protocol's operators (7.3).
const COND_OPS = {
	equals: '==', notequals: '!=', contains: '=~', notcontains: '!~',
	greaterthan: '>', greaterorequal: '>=', lessthan: '<', lessorequal: '<='
};

function sensorById(id) {
	for (let i = 0; i < sensorCatalog.length; i++) {
		if (sensorCatalog[i].id === parseInt(id, 10)) { return sensorCatalog[i]; }
		}
	return null;
	}

// A retrieve row whose sensor accepts parameters shows one value input per
// declared field (prefilled with the default); anything else shows none.
function renderParams(row, sensorId) {
	const box = row.querySelector('.param-fields');
	if (!box) { return; }
	box.innerHTML = '';
	const s = sensorById(sensorId);
	if (!s || !s.withparams || s.params.length === 0) { return; }
	s.params.forEach(p => {
		const label = document.createElement('span');
		label.textContent = p.field + ': ';
		const inp = document.createElement('input');
		inp.type = 'text';
		inp.className = 'param-input';
		inp.dataset.field = p.field;
		inp.value = p.default;
		inp.maxLength = 1024;
		inp.style.fontSize = '15px';
		inp.style.padding = '3px';
		inp.style.width = '120px';
		inp.style.marginLeft = '4px';
		box.appendChild(label);
		box.appendChild(inp);
		});
	}

// One condition row -> a protocol leaf {sid, op, value}.
function condRowLeaf(row) {
	const sel = row.querySelector('.sensor-select');
	const op = row.querySelector('.row-dropdown');
	const val = row.querySelector('.cond-value');
	return {
		sid: parseInt(sel.value, 10),
		op: COND_OPS[op.value] || op.value,
		value: val.value
		};
	}

// The row that carries a block's trailing AND/OR: the row itself, or the
// group's last row (mirrors insertLogicalOperators' anchor).
function condAnchor(block) {
	if (block.classList.contains('group-container')) {
		const rows = block.querySelectorAll(':scope > .list-item');
		return rows.length ? rows[rows.length - 1] : null;
		}
	return block;
	}

// A container's blocks (rows and group containers) -> a condition subtree.
// Consecutive blocks are joined with the operator stored on the preceding
// block's anchor, left-associatively: A op1 B op2 C = (A op1 B) op2 C.
function buildCondTree(container) {
	const blocks = Array.from(container.children).filter(el =>
		el.classList.contains('list-item') || el.classList.contains('group-container'));
	if (blocks.length === 0) { return null; }
	let node = blocks[0].classList.contains('group-container')
		? buildCondTree(blocks[0])
		: condRowLeaf(blocks[0]);
	for (let i = 1; i < blocks.length; i++) {
		const anchor = condAnchor(blocks[i - 1]);
		const opSel = anchor ? anchor.querySelector('.logical-operator') : null;
		const logic = opSel ? opSel.value : 'AND';
		const right = blocks[i].classList.contains('group-container')
			? buildCondTree(blocks[i])
			: condRowLeaf(blocks[i]);
		node = { logic: logic, left: node, right: right };
		}
	return node;
	}

function condRowsComplete() {
	const rows = document.querySelectorAll('#from-list .list-item');
	if (rows.length === 0) { return false; }
	let ok = true;
	rows.forEach(row => {
		const sel = row.querySelector('.sensor-select');
		const val = row.querySelector('.cond-value');
		if (!sel || !sel.value || !val || val.value.trim() === '') { ok = false; }
		});
	return ok;
	}

// Submit is enabled with at least one retrieve sensor, and - when the query
// is condition-filtered - every condition row complete.
function updateSubmitState() {
	const btn = document.getElementById('querygo');
	if (!btn) { return; }
	let sensors = 0;
	document.querySelectorAll('#get-list .list-item').forEach(row => {
		const sel = row.querySelector('.sensor-select');
		if (sel && sel.value) { sensors++; }
		});
	let ok = sensors > 0;
	if (ok && document.getElementById('targets').value === 'matching') {
		ok = condRowsComplete();
		}
	btn.disabled = !ok;
	}

function submitQuery() {
	const sensors = [];
	document.querySelectorAll('#get-list .list-item').forEach(row => {
		const sel = row.querySelector('.sensor-select');
		if (!sel || !sel.value) { return; }
		const s = { sid: parseInt(sel.value, 10) };
		const params = {};
		row.querySelectorAll('.param-input').forEach(inp => { params[inp.dataset.field] = inp.value; });
		if (Object.keys(params).length > 0) { s.params = params; }
		sensors.push(s);
		});
	if (sensors.length === 0) { return; }
	const body = { target: 'all', action: 'query', sensors: sensors };
	if (document.getElementById('targets').value === 'matching') {
		if (!condRowsComplete()) { return; }
		body.conditions = buildCondTree(document.getElementById('from-list'));
		}
	fetch('/api/commands.php', {
		method: 'POST',
		credentials: 'same-origin',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify(body)
		})
		.then(r => r.json().then(d => ({ ok: r.ok, d: d })))
		.then(({ ok, d }) => {
			if (ok && d && d.ok) {
				window.location.href = '/modules.php?view=queryresults';
				}
			else {
				LuminumOverlay.show({
					title: 'Query Error',
					message: (d && d.error) ? d.error : 'The query could not be submitted.',
					buttons: [{ label: 'OK', onclick: function () { LuminumOverlay.hide(); } }]
					});
				}
			})
		.catch(() => {
			LuminumOverlay.show({
				title: 'Query Error',
				message: 'The query could not be submitted.',
				buttons: [{ label: 'OK', onclick: function () { LuminumOverlay.hide(); } }]
				});
			});
	}

window.addEventListener('DOMContentLoaded', () => {
	// Capture pristine markup before any rows are added or mutated
	initialGetList = document.getElementById('get-list').innerHTML;
	initialFromList = document.getElementById('from-list').innerHTML;

	document.getElementById('resetform').addEventListener('click', resetForm);
	updateRemoveButtons(document.getElementById('get-list'));
	updateRemoveButtons(document.getElementById('from-list'));
	updateDragHandleIcons(document.getElementById('get-list'));
	updateDragHandleIcons(document.getElementById('from-list'));
	attachHandlers();
	initSortable();

	// The sortable re-inits replace the list containers, so the builder's
	// own listeners live on document (delegated) instead.
	document.addEventListener('change', (e) => {
		if (e.target.classList && e.target.classList.contains('sensor-select')) {
			const row = e.target.closest('.list-item');
			if (row && row.closest('#get-list')) { renderParams(row, e.target.value); }
			}
		updateSubmitState();
		});
	document.addEventListener('input', updateSubmitState);
	updateSubmitState();
	});

let initialGetList = '';
let initialFromList = '';

function resetForm() {
	const getContainer = document.getElementById('get-list');
	const fromContainer = document.getElementById('from-list');

	getContainer.innerHTML = initialGetList;
	fromContainer.innerHTML = initialFromList;

	document.getElementById('targets').selectedIndex = 0;
	document.getElementById('tsuffix').textContent = ' the following condition:';
	fromContainer.style.opacity = '1';

	initSortable();
	updateSubmitState();
	}

function addRow(event) {
	const addBtn = event.target;
	const listItem = addBtn.closest('.list-item');
	const container = listItem.parentElement;
	const newRow = listItem.cloneNode(true);

	newRow.querySelectorAll('input').forEach(input => input.value = '');
	newRow.querySelectorAll('select').forEach(select => select.selectedIndex = 0);
	const pbox = newRow.querySelector('.param-fields');
	if (pbox) { pbox.innerHTML = ''; }

	// Insert right after the clicked row (not at the end of the container).
	// Appending to the end put a new row *after* a group and dropped the
	// group's trailing AND/OR onto the group's last row, which read as an
	// operator inside the group.
	listItem.after(newRow);

	// Update the whole edited list (not just the group) so remove buttons and
	// drag handles stay consistent whether the row was added at top level or
	// inside a group
	const root = container.closest('#from-list') ? document.getElementById('from-list') : container;
	updateRemoveButtons(root);
	updateDragHandleIcons(root);
	attachHandlers();

	//if (container.id === 'from-list') { insertLogicalOperators(container); }
	if (container.closest('#from-list')) {
		// Always re-process from the root so the operator between a group and
		// the next top-level row is kept when adding inside a group
		insertLogicalOperators(document.getElementById('from-list'));
		document.getElementById("tsuffix").textContent = "the following conditions:";
		}
	updateSubmitState();
	}

function removeRow(event) {
	const listItem = event.target.closest('.list-item');
	const container = listItem.parentElement;
	const inFromList = container.closest('#from-list') !== null;
	listItem.remove();

	// A group left with a single row has no AND/OR to join and no collapse
	// button, so it would be stuck; un-group it (and any parent group that
	// drops to one row as a result)
	if (inFromList) {
		let g = container;
		while (g && g.classList.contains('group-container') && g.querySelectorAll('.list-item').length <= 1) {
			while (g.firstChild) {
				g.before(g.firstChild);
				}
			const parent = g.parentElement;
			g.remove();
			g = parent;
			}
		}

	// After a collapse the group container is detached, so re-fetch the live
	// root of the edited list
	const root = inFromList ? document.getElementById('from-list') : container;
	updateRemoveButtons(root);
	updateDragHandleIcons(root);
	attachHandlers();

	//if (container.id === 'from-list') { insertLogicalOperators(container); }
	if (inFromList) {
		// Always re-process from the root so the operator between a group and
		// the next top-level row is kept when removing inside a group
		insertLogicalOperators(document.getElementById('from-list'));
		}
	updateSubmitState();
	}

function updateRemoveButtons(container) {
	const rows = container.querySelectorAll('.list-item');
	rows.forEach((row, index) => {
		const existingRemove = row.querySelector('.remove');

		if (existingRemove) existingRemove.remove();

		if (index > 0) {
			const removeBtn = document.createElement('img');
			removeBtn.src = 'icons/remove.png';
			removeBtn.className = 'remove';
			removeBtn.style.cursor = 'pointer';
			removeBtn.style.marginRight = '3px';
			removeBtn.style.marginBottom = '3px';
			removeBtn.style.verticalAlign = 'middle';

			const addBtn = row.querySelector('.add');
			row.insertBefore(removeBtn, addBtn);
			removeBtn.addEventListener('click', removeRow);
			}
		});
  	}

function attachHandlers() {
	const images = document.querySelectorAll('img');
	images.forEach(image => {
		if (image.getAttribute('src') === '/icons/collapsegroup.png' || image.getAttribute('src') === '/icons/addgroup.png') {
			image.addEventListener('click', toggleGroup);
			}
		});
	document.querySelectorAll('.add').forEach(addBtn => {
		addBtn.removeEventListener('click', addRow);
		addBtn.addEventListener('click', addRow);
		});

	document.querySelectorAll('.remove').forEach(removeBtn => {
		removeBtn.removeEventListener('click', removeRow);
		removeBtn.addEventListener('click', removeRow);
		});
	}

function updateDragHandleIcons(container) {
	const rows = container.querySelectorAll('.list-item');
	const dragIcon = rows.length > 1 ? 'reorder.png' : 'reorder-dis.png';

	rows.forEach(row => {
		const dragHandle = row.querySelector('.drag-handle');
		if (dragHandle) {
			if (rows.length > 1) {
				dragHandle.style.opacity = 1;
				dragHandle.style.pointerEvents = 'auto';
				dragHandle.src = `/icons/${dragIcon}`;
				}
			else {
				dragHandle.style.opacity = 0;
				dragHandle.style.pointerEvents = 'none';
				dragHandle.src = '/icons/reorder-dis.png';
				}
			}
		});
	}

function insertLogicalOperators(container) {
	// Clear existing operators and group buttons
	container.querySelectorAll('.logical-operator, .logical-operator-br, .group-button').forEach(el => el.remove());

	// A "block" is a single row or a group container. Operators go between
	// consecutive blocks, so a row followed by a group keeps its AND/OR
	// dropdown (now sitting between the row and the group).
	function getBlocks(parent) {
		return Array.from(parent.children).filter(el =>
			el.classList.contains('list-item') || el.classList.contains('group-container'));
	}

	// The row that carries a block's trailing operator: the row itself, or
	// the group's last row.
	function anchorOf(block) {
		if (block.classList.contains('group-container')) {
			const rows = block.querySelectorAll(':scope > .list-item');
			return rows.length ? rows[rows.length - 1] : null;
			}
		return block;
	}

	function processBlocks(parent) {
		const blocks = getBlocks(parent);

		if (container.id === 'from-list' && container.querySelectorAll('.list-item').length == 1) {
			document.getElementById("tsuffix").textContent = "the following condition:";
			}

		for (let i = 0; i < blocks.length - 1; i++) {
			const anchor = anchorOf(blocks[i]);
			if (!anchor) continue;

			const br = document.createElement('br>');
			br.className = 'logical-operator-br';

			const select = document.createElement('select');
			select.className = 'logical-operator';
			select.style.width = '75px';
			select.style.margin = '5px 0 5px 30px';
			select.style.fontSize = '15px';
			select.style.height = '30px';

			select.appendChild(new Option('AND', 'AND'));
			select.appendChild(new Option('OR', 'OR'));

			const groupImg = document.createElement('img');
			// A row directly above a group carries the ungroup (collapse)
			// button; every other row carries the group (add) button, which
			// also creates nested groups from inside a group
			groupImg.src = blocks[i + 1].classList.contains('group-container') ? '/icons/collapsegroup.png' : '/icons/addgroup.png';
			groupImg.className = 'group-button';
			groupImg.style.width = '24px';
			groupImg.style.height = '24px';
			groupImg.style.marginBottom = '3px';
			groupImg.style.cursor = 'pointer';
			groupImg.style.marginLeft = '8px';
			groupImg.style.verticalAlign = 'middle';
			groupImg.addEventListener('click', toggleGroup);

			anchor.appendChild(br);
			anchor.appendChild(select);
			anchor.appendChild(groupImg);
		}
	}

	// Process top-level blocks (rows and groups)
	processBlocks(container);

	// Process each group's rows individually
	container.querySelectorAll('.group-container').forEach(group => {
		processBlocks(group);
	});
}

function toggleGroup(event) {
	const groupIcon = event.target;
	const row = groupIcon.closest('.list-item');

	if (groupIcon.src.includes('addgroup.png')) {
		// Start grouping: indent the row below the button and add a new empty row to the group
		let nextRow = row.nextElementSibling;
		if (nextRow && nextRow.classList.contains('group-container')) {
			// the row below is the first row of an existing group; pull it out
			nextRow = nextRow.querySelector(':scope > .list-item');
			}
		if (!nextRow) return;
		const oldParent = nextRow.parentElement;

		const groupContainer = document.createElement('div');
		groupContainer.className = 'group-container';
		groupContainer.style.marginLeft = '100px';
		groupContainer.style.borderLeft = '4px solid #aaa';
		groupContainer.style.paddingLeft = '10px';

		row.after(groupContainer);
		groupContainer.appendChild(nextRow);
		if (oldParent.classList.contains('group-container') && oldParent.children.length === 0) {
			oldParent.remove();
			}

		const newRow = nextRow.cloneNode(true);
		newRow.querySelectorAll('input').forEach(input => input.value = '');
		newRow.querySelectorAll('select').forEach(select => select.selectedIndex = 0);
		const pbox = newRow.querySelector('.param-fields');
		if (pbox) { pbox.innerHTML = ''; }
		newRow.querySelectorAll('.logical-operator, .logical-operator-br, .group-button, .remove').forEach(el => el.remove());
		groupContainer.appendChild(newRow);
		}
	else {
		// Collapse: the ungroup button sits above the group it collapses. That
		// group is normally the row's next sibling (the row sits directly above
		// the group, including nested groups). When the row is instead the last
		// row of a group that is itself followed by another group, the target is
		// the next sibling of that group.
		let groupContainer = row.nextElementSibling;
		if (!groupContainer || !groupContainer.classList.contains('group-container')) {
			const parent = row.parentElement;
			if (parent && parent.classList.contains('group-container')) {
				groupContainer = parent.nextElementSibling;
				}
			}
		if (groupContainer && groupContainer.classList.contains('group-container')) {
			while (groupContainer.firstChild) {
				groupContainer.before(groupContainer.firstChild);
				}
			groupContainer.remove();
			}
		}

	const getContainer = document.getElementById('get-list');
	const fromContainer = document.getElementById('from-list');
	updateRemoveButtons(getContainer);
	updateRemoveButtons(fromContainer);
	updateDragHandleIcons(getContainer);
	updateDragHandleIcons(fromContainer);
	insertLogicalOperators(fromContainer);
	attachHandlers();
	initSortable();
	updateSubmitState();
	}

function switchTab(evt, configSect) {
	var i, x, tablinks;
	x = document.getElementsByClassName("configtab");

	for (i = 0; i < x.length; i++) {
		x[i].style.display = "none";
		}

	tablinks = document.getElementsByClassName("tablink");
	for (i = 0; i < x.length; i++) {
		tablinks[i].className = tablinks[i].className.replace(" tabbarsel", "");
		}

	document.getElementById(configSect).style.display = "block";
	evt.currentTarget.className += " tabbarsel";
	}

function selectSuffix() {
	var val = document.getElementById("targets").value;
	const itemCount = document.querySelectorAll('#from-list .list-item').length;

	if (val == "all") {
		document.getElementById("tsuffix").textContent = "";
		document.getElementById("from-list").style.opacity = "0";
		}
	else {
		if (itemCount > 1) { document.getElementById("tsuffix").textContent = "the following conditions:"; }
		else { document.getElementById("tsuffix").textContent = "the following condition:"; }
		document.getElementById("from-list").style.opacity = "1";
		}
	updateSubmitState();
	}

function initSortable() {
	const getContainer = document.getElementById('get-list');
	const fromContainer = document.getElementById('from-list');
	getContainer.replaceWith(getContainer.cloneNode(true));
	fromContainer.replaceWith(fromContainer.cloneNode(true));
	// Re-fetch: the variables above still reference the detached originals
	updateRemoveButtons(document.getElementById('get-list'));
	updateRemoveButtons(document.getElementById('from-list'));
	updateDragHandleIcons(document.getElementById('get-list'));
	updateDragHandleIcons(document.getElementById('from-list'));
	attachHandlers();

	['get-list', 'from-list'].forEach(id => {
		const container = document.getElementById(id);
		// Init sortable for main container
		new Sortable(container, {
			handle: '.drag-handle',
			animation: 150,
			filter: '.group-container',
			// Without this, Sortable preventDefault()s any mousedown that lands
			// inside a filtered .group-container, which blocks the browser from
			// focusing the group's inputs/selects (and opening the dropdowns)
			preventOnFilter: false,
			ghostClass: 'sortable-ghost',
			onStart(evt) { evt.item.classList.add('hidden-during-drag'); },
			onEnd(evt) {
				evt.item.classList.remove('hidden-during-drag');
				updateRemoveButtons(container);
				updateDragHandleIcons(container);
				attachHandlers();
				if (container.id === 'from-list') insertLogicalOperators(container);
				updateSubmitState();
				}
			});

		// Init sortable for each group container
		container.querySelectorAll('.group-container').forEach(group => {
			new Sortable(group, {
				handle: '.drag-handle',
				animation: 150,
				group: {
					name: 'group-' + Math.random(), // unique per group
					pull: false, // don't allow dragging items *out*
					put: false   // don't allow dragging items *in*
					},
				ghostClass: 'sortable-ghost',
				onStart(evt) { evt.item.classList.add('hidden-during-drag'); },
				onEnd(evt) {
					evt.item.classList.remove('hidden-during-drag');
					// Re-process from the root so the AND/OR moves to the new
					// first row of the group (it's a child of a row, so dragging
					// carries it to the wrong row)
					const root = document.getElementById('from-list');
					updateRemoveButtons(root);
					updateDragHandleIcons(root);
					attachHandlers();
					insertLogicalOperators(root);
					updateSubmitState();
					}
				});
			});
		});
	}
</script>
