<?php
//
// Query builder. The markup and the builder's own JS (row add/remove,
// drag-sort, grouping, the AND/OR operators between the condition rows)
// are the page's own; the PHP below only loads the sensor catalog (ID +
// name) so the typed sensor fields can be resolved to sensor IDs, and
// layout/querybuilder.js turns what the operator typed into the
// /api/commands.php query statement (protocol 7.3): broadcast to all
// endpoints, only the endpoints on which the condition tree evaluates
// true answer.
//
mysqli_select_db($db, "CONTENT") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
$sq = mysqli_query($db, "select ID,NAME,RTYPE from SENSORS order by NAME");
$sensorlist = [];
while ($srow = mysqli_fetch_assoc($sq)) {
	$sensorlist[] = ['id' => (int)$srow['ID'], 'name' => $srow['NAME'], 'rtype' => $srow['RTYPE']];
}
// The catalog for the builder's JS: the typed sensor fields resolve to sensor
// IDs, and each sensor's result type (RTYPE) drives the condition operator
// options and the sensor autocomplete.
$sensorjson = json_encode($sensorlist, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);

// The query ID (the query command's COMMANDS.ID - the "command" value
// /api/commands.php returns when the query is submitted): when the page is
// passed one, the page shows that query's results directly - no tab bar, the
// results table is the whole page - polled live from
// /api/queryresults.php?id=... (the old standalone Query Results page is
// consolidated into this one).
$queryid = 0;
if (isset($_GET['id']) && ctype_digit($_GET['id'])) {
	$queryid = (int)$_GET['id'];
}
$showresults = $queryid > 0;
// ?tab=saved opens the page on the Saved Queries tab (the header menu's
// "Saved Queries" link points here - the old standalone Saved Queries page
// is gone).
$showsaved = !$showresults && isset($_GET['tab']) && $_GET['tab'] === 'saved';
?>
<div class="content">
	<h1>Luminum Query</h1>

<?php if ($showresults) { ?>
<div>
	<div class="module-content">
		<div style="display: block; width: 100%; text-align: right;">
			<table id="qrtable" style="margin-top: 10px; text-align: left;">
			<tr><td id="qrtopcell" colspan="3"><div style="position: absolute; padding-top: 5px; padding-left: 5px;"><img id="qrrefresh" src="icons/refresh.png" style="cursor: pointer; width: 15px; height: 15px; vertical-align: top;" onclick="qrRefresh()">&nbsp;&nbsp;<span id="qrcount">0</span> of <span id="qrtotal">0</span> Items <span id="qrselcount"></span></div><div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" id="qrfilter" style="font-size: 15px; padding: 3px; margin-top: 0;" maxlength="64"></div></td></tr>
			<tbody id="qrtable-head"></tbody>
			<tbody data-luminum-body id="qrtable-body"></tbody>
			<tr style="height: 35px;"><td id="qrfootcell" colspan="3"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i><span id="qrfootprefix">Processing Query...</span> <span id="queryms">0.00</span> Seconds</i></div></td></tr>
			</table>
		</div>
	</div>
</div>
<?php } else { ?>
<div class="pagecol">
	<!-- <div class="module-content" style="display: flex; justify-content: space-between; align-items: flex-start;"> -->
	<div class="module-content" style="padding: 0;">
		<div class="tabbar tabbarback">
			<button type="button" class="tabbaritem tabbutton tablink<?php print $showsaved ? '' : ' tabbarsel'; ?>" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Builder')">Query Builder</button>
			<button type="button" class="tabbaritem tabbutton tablink<?php print $showsaved ? ' tabbarsel' : ''; ?>" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Saved')">Saved Queries</button>
		</div>
		<!-- <div class="main-content"> -->
		<div id="Builder" class="configtab" style="<?php print $showsaved ? 'display: none;' : ''; ?>">
			<div style="margin: 20px;">
				<p>
				<span style="font-size: 20px; font-weight: bold; color: #444;">I want to retrieve:</span>
				</p>
				<div id="get-list">
					<div class="list-item" style="margin-bottom: 5px;"><img src="/icons/reorder-dis.png" class="drag-handle" style="vertical-align: middle"> <input type="text" placeholder="Sensor" style="width: 200px;" maxlength="128"> <img src="/icons/add.png" class="add" style="vertical-align: middle; margin-bottom: 3px;"></div>
				</div>

				<p style="margin-top: 20px;">
				<span style="font-size: 20px; font-weight: bold; color: #444;">From</span> <select style="font-size: 15px; height: 30px; margin-left: 2px; margin-right: 2px;" name="targets" id="targets" class="target-dropdown" onchange="selectSuffix();"><option name="matching" value="matching" default="default">endpoints matching</option><option name="all" value="all">all endpoints</option></select> <span id="tsuffix" style="font-size: 20px; font-weight: bold; color: #444;"> the following condition:</span>
				</p>
				<!-- The condition row's operator dropdown and value field
				     start disabled: layout/querybuilder.js enables them
				     once the row's sensor field resolves to a valid
				     sensor (applyRowType drives the disabled state). -->
				<div id="from-list">
					<div class="list-item"><img src="/icons/reorder-dis.png" class="drag-handle" style="vertical-align: middle;"> <input type="text" placeholder="Sensor" style="width: 200px;" maxlength="128"> <select class="row-dropdown" style="font-size: 15px; height: 30px; margin-left: 5px; margin-right: 10px;" name="fromop" disabled="disabled"><option name="equals" value="equals">==</option><option name="notequals" value="notequals">!=</option><option name="contains" value="contains">=~</option><option name="notcontains" value="notcontains">!~</option><option name="greaterthan" value="greaterthan">&gt;</option><option name="greaterthan" value="greaterorequal">&gt;=</option><option name="lessthan" value="lessthan">&lt;</option><option name="greaterthan" value="lessorequal">&lt;=</option></select><span class="bool-op" style="display: none; font-size: 15px; height: 30px; line-height: 30px; margin-left: 5px; margin-right: 10px; vertical-align: middle;">==</span><input type="text" placeholder="Value" maxlength="128" disabled="disabled"> <select class="bool-value" style="display: none; font-size: 15px; height: 30px; width: 100px;"><option value="TRUE">TRUE</option><option value="FALSE">FALSE</option></select> <img src="/icons/add.png" class="add" style="vertical-align: middle; margin-bottom: 3px;"></div>
				</div>
			</div>
		</div>
		<div id="Saved" class="configtab" style="<?php print $showsaved ? '' : 'display: none;'; ?>">
			<!-- The Saved Queries table: the console's standard table - the
			     displayed-of-total count with the (N Selected) suffix, the
			     right-hand filter box, the selection column, and the
			     footer - the same structure as the main table pages. The
			     Structure column renders the query's full text-based
			     interpretation (LuminumQueryBuilder.queryStructure on the
			     saved query's payload). Saved queries have no storage yet,
			     so the table renders its empty state; rows (radio
			     name="savedquery" id="ID<n>" class "savedqueryrow",
			     onchange="sqRowHighlight(); sqSelCount();", cells
			     <n>A..E) render here once saving exists - the radios form
			     one group, so exactly one saved query can be selected.
			     Each row's radio carries the query's JSON payload (the
			     /api/commands.php statement) in data-payload - Copy to
			     Builder reads it to repopulate the builder form. The
			     header row's checkbox is a permanently disabled dummy:
			     a radio group has no select-all. -->
			<div style="padding: 5px 20px 20px 20px;">
				<table style="margin-top: 10px; table-layout: fixed;">
				<colgroup><col style="width: 32px;"><col><col><col style="width: 100px;"><col style="width: 120px;"></colgroup>
				<tr><td colspan="5"><div style="position: absolute; padding-top: 7px; padding-left: 5px;"><span id="sqviscount">0</span> of <span id="sqtotcount">0</span> items <span id="sqselcount"></span></div><div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" id="savedqueriesfilter" style="font-size: 15px; padding: 3px; margin-top: 0;" disabled="disabled" maxlength="64"></div></td></tr>
				<tr><td><input type="checkbox" disabled="disabled"></td><td>Name</td><td>Structure</td><td>Author</td><td>Create Date</td></tr>
				<tr><td colspan="5" style="text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;">No Results</td></tr>
				<tr style="height: 35px;"><td colspan="5"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i>Query Completed in 0.00 Seconds</i></div></td></tr>
				</table>
			</div>
		</div>
	</div>
	<!-- The left form button follows the active tab: Reset Form on the
	     Query Builder tab, Copy to Builder on the Saved Queries tab -
	     switchTab swaps the label, and the initial label matches ?tab=saved.
	     Copy to Builder is disabled until a saved query is selected (the
	     initial disabled state matches ?tab=saved; layout/querybuilder.js
	     keeps it in step afterwards). Delete Selected sits to its left and
	     is a Saved-tab-only button (switchTab hides it on the Query Builder
	     tab, where it could never be enabled): disabled until a saved query
	     is selected - the delete action itself waits for saved-query
	     storage (ToDo: Query Loading - Not Started). Run Query processes
	     only the visible tab: layout/querybuilder.js enables it per tab (a
	     valid builder on the Query Builder tab, exactly one selected saved
	     query on the Saved Queries tab) and submits only that tab's
	     contents - a tab switch is a click, so the document-level state
	     listener re-enables or disables it as the operator moves between
	     the tabs. -->
	<div id="formbuttons" class="pageactions" style="padding-top: 10px; margin-bottom: 0;">
		<button id="sqdelete" class="formgo" style="<?php print $showsaved ? '' : 'display: none;'; ?>margin-right: 0;" disabled="disabled">Delete Selected</button> <button id="resetform" class="formgo" style="margin-right: 0;"<?php print $showsaved ? ' disabled="disabled"' : ''; ?>><?php print $showsaved ? 'Copy to Builder' : 'Reset Form'; ?></button> <button id="querygo" class="formgo" style="margin-right: 0;" disabled="disabled">Run Query</button>
	</div>

</div>
<?php } ?>

<?php if (!$showresults) { ?>
<script src="/layout/Sortable.min.js"></script>

<script>
window.addEventListener('DOMContentLoaded', () => {
	// Capture pristine markup before any rows are added or mutated
	initialGetList = document.getElementById('get-list').innerHTML;
	initialFromList = document.getElementById('from-list').innerHTML;

	document.getElementById('resetform').addEventListener('click', function () {
		// The button follows the active tab: Reset Form on the Query
		// Builder tab, Copy to Builder on the Saved Queries tab
		if (document.getElementById('Saved').style.display !== 'none') {
			copyToBuilder();
			}
		else {
			resetForm();
			}
		});
	updateRemoveButtons(document.getElementById('get-list'));
	updateRemoveButtons(document.getElementById('from-list'));
	updateDragHandleIcons(document.getElementById('get-list'));
	updateDragHandleIcons(document.getElementById('from-list'));
	attachHandlers();
	initSortable();
	// The builder leads with the first retrieve field: it takes focus on
	// load (after initSortable, which replaces the list containers with
	// clones, so the element must be re-queried)
	const firstField = document.querySelector('#get-list .list-item input');
	if (firstField) { firstField.focus(); }
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
	}

function copyToBuilder() {
	// The module drives the copy: it validates the selection, reads the
	// selected query's payload, resets and populates the builder, and
	// switches to the Query Builder tab
	LuminumQueryBuilder.copyToBuilder(window.luminumSensorCatalog);
	}

function addRow(event) {
	const addBtn = event.target;
	const listItem = addBtn.closest('.list-item');
	const container = listItem.parentElement;
	const newRow = listItem.cloneNode(true);

	newRow.querySelectorAll('input').forEach(input => input.value = '');
	newRow.querySelectorAll('select').forEach(select => select.selectedIndex = 0);

	// Insert right after the clicked row (not at the end of the container).
	// Appending to the end put a new row *after* a group and dropped the
	// group's trailing AND/OR onto the group's last row, which read as an
	// operator inside the group.
	listItem.after(newRow);

	// The new row's first field takes focus so the operator can type
	// immediately
	const newField = newRow.querySelector('input');
	if (newField) { newField.focus(); }

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

	function processBlocks(parent) {
		const blocks = getBlocks(parent);

		if (container.id === 'from-list' && container.querySelectorAll('.list-item').length == 1) {
			document.getElementById("tsuffix").textContent = "the following condition:";
			}

		for (let i = 0; i < blocks.length - 1; i++) {
			const isGroup = blocks[i].classList.contains('group-container');

			const br = document.createElement('br');
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
			// A block directly above a group carries the ungroup (collapse)
			// button; every other block carries the group (add) button, which
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

			if (isGroup) {
				// The operator that joins a group to the next block sits
				// outside the group, below it - on the group's last row it
				// would render inside the group's indent and border
				blocks[i].after(groupImg);
				blocks[i].after(select);
				blocks[i].after(br);
				}
			else {
				blocks[i].appendChild(br);
				blocks[i].appendChild(select);
				blocks[i].appendChild(groupImg);
				}
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
	// The operator triple that carries the button either sits inside the
	// anchor row (row) or, when the block before the operator is a group,
	// as the siblings immediately after that group (row === null); either
	// way the block the operator joins to is the button's next sibling
	const row = groupIcon.closest('.list-item');
	const nextBlock = row ? row.nextElementSibling : groupIcon.nextElementSibling;

	if (groupIcon.src.includes('addgroup.png')) {
		// Start grouping: indent the row below the button and add a new empty row to the group
		let nextRow = nextBlock;
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

		(row || groupIcon).after(groupContainer);
		groupContainer.appendChild(nextRow);
		if (oldParent.classList.contains('group-container') && oldParent.children.length === 0) {
			oldParent.remove();
			}

		const newRow = nextRow.cloneNode(true);
		newRow.querySelectorAll('input').forEach(input => input.value = '');
		newRow.querySelectorAll('select').forEach(select => select.selectedIndex = 0);
		newRow.querySelectorAll('.logical-operator, .logical-operator-br, .group-button, .remove').forEach(el => el.remove());
		groupContainer.appendChild(newRow);
		// The group's new empty row takes focus after the sortable re-init
		// (which replaces the containers with clones) - mark it so it can
		// be re-found in the live tree
		newRow.setAttribute('data-focusrow', '1');
		}
	else {
		// Collapse: the ungroup button sits above the group it collapses, so
		// the target is the button's next sibling block - the row's next
		// sibling when the button is in a row (the row sits directly above
		// the group, including nested groups), or the group that follows a
		// group's trailing operator when the button sits as a sibling after
		// a group.
		let groupContainer = nextBlock;
		if (row && (!groupContainer || !groupContainer.classList.contains('group-container'))) {
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
	// A newly grouped row takes focus (the containers were replaced with
	// clones by initSortable, so re-find the marked row in the live tree)
	const focusRow = document.querySelector('#from-list [data-focusrow]');
	if (focusRow) {
		focusRow.removeAttribute('data-focusrow');
		const field = focusRow.querySelector('input');
		if (field) { field.focus(); }
		}
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
					}
				});
			});
		});
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
	// The form button follows the active tab: Reset Form on the Query
	// Builder tab, Copy to Builder on the Saved Queries tab
	document.getElementById("resetform").textContent = (configSect === "Saved") ? "Copy to Builder" : "Reset Form";
	// Delete Selected is a Saved-tab-only button
	document.getElementById("sqdelete").style.display = (configSect === "Saved") ? "" : "none";
	}
</script>

<script src="/layout/querybuilder.js"></script>

<script>
window.addEventListener('DOMContentLoaded', () => {
	// The sensor catalog the builder's wiring resolves typed sensor fields
	// against (also read by Copy to Builder)
	window.luminumSensorCatalog = <?php print $sensorjson; ?>;
	LuminumQueryBuilder.init(window.luminumSensorCatalog);
	});
</script>

<script src="layout/table.js"></script>
<script>
// The Saved Queries tab's table wiring - the same client-side behaviour as
// the main table pages: the filter hides non-matching rows and keeps the
// displayed count in step. The rows are radio buttons (one selection), so
// there is no select-all - the header row's checkbox is a permanently
// disabled dummy - and selecting a row highlights it and shows the
// (1 Selected) suffix.
LuminumTable.attachTextFilter('savedqueriesfilter', function (visible) {
	document.getElementById('sqviscount').textContent = visible;
	});

function sqRowHighlight() {
	// The rows are one radio group, so the row being deselected never
	// fires its own onchange: re-paint every row from its radio's state
	document.querySelectorAll('input[class="savedqueryrow"]').forEach(radio => {
		var rownum = radio.id.substring(2);
		var bgcolor = radio.checked == true ? "#686993" : "#494a69";
		document.getElementById(rownum + "A").style.backgroundColor = bgcolor;
		document.getElementById(rownum + "B").style.backgroundColor = bgcolor;
		document.getElementById(rownum + "C").style.backgroundColor = bgcolor;
		document.getElementById(rownum + "D").style.backgroundColor = bgcolor;
		document.getElementById(rownum + "E").style.backgroundColor = bgcolor;
		});
	}

function sqSelCount() {
	document.getElementById("sqselcount").textContent = document.querySelector('.savedqueryrow:checked') ? '(1 Selected)' : '';
	}
</script>
<?php } ?>

<?php if ($showresults) { ?>
<script src="/layout/table.js"></script>
<script src="/layout/queryresults.js"></script>
<script>
'use strict';

var qrHandle = LuminumQueryResults.init(<?php print $queryid; ?>);

function qrRefresh() {
	var btn = document.getElementById('qrrefresh');
	if (btn.className === 'refresh') { return; }
	btn.className = 'refresh';
	btn.style.cursor = 'progress';
	var done = function () { btn.className = ''; btn.style.cursor = 'pointer'; };
	var p = qrHandle ? qrHandle.refresh() : null;
	if (p && p.then) { p.then(done, done); } else { done(); }
}
</script>
<?php } ?>
