<div class="content">
	<h1>Luminum Query</h1>

<div>
	<div class="module-content" style="display: flex; justify-content: space-between; align-items: flex-start;">
		<div class="main-content">
			<p style="margin-top: 10px;">
			<span style="font-size: 20px; font-weight: bold; color: #444;">I want to retrieve:</span>
			</p>
			<div id="get-list">
				<div class="list-item" style="margin-bottom: 5px;"><img src="/icons/reorder-dis.png" class="drag-handle" style="vertical-align: middle"> <input type="text" placeholder="Sensor" style="width: 200px;" maxlength="128"> <img src="/icons/add.png" class="add" style="vertical-align: middle; margin-bottom: 3px;"></div>
			</div>

			<p style="margin-top: 20px;">
			<span style="font-size: 20px; font-weight: bold; color: #444;">From</span> <select style="font-size: 15px; height: 30px; margin-left: 2px; margin-right: 2px;" name="targets" id="targets" class="target-dropdown" onchange="selectSuffix();"><option name="matching" value="matching" default="default">endpoints matching</option><option name="all" value="all">all endpoints</option></select> <span id="tsuffix" style="font-size: 20px; font-weight: bold; color: #444;"> the following condition:</span>
			</p>
			<div id="from-list">
				<div class="list-item"><img src="/icons/reorder-dis.png" class="drag-handle" style="vertical-align: middle;"> <input type="text" placeholder="Sensor" style="width: 200px;" maxlength="128"> <select class="row-dropdown" style="font-size: 15px; height: 30px; margin-left: 5px; margin-right: 10px;" name="fromop"><option name="equals" value="equals">==</option><option name="notequals" value="notequals">!=</option><option name="contains" value="contains">=~</option><option name="greaterthan" value="greaterthan">&gt;</option><option name="greaterthan" value="greaterorequal">&gt;=</option><option name="lessthan" value="lessthan">&lt;</option><option name="greaterthan" value="lessorequal">&lt;=</option></select><input type="text" placeholder="Value" maxlength="128"> <img src="/icons/add.png" class="add" style="vertical-align: middle; margin-bottom: 3px;"></div>
			</div>
		</div>
	</div>
	<div style="width: 100%; text-align: right; padding-top: 10px;">
		<button id="querygo" class="formgo" style="margin-right: 0;" disabled="disabled">Submit Query</button> <button id="resetform" class="formgo" style="margin-left: 0;">Reset Form</button>
	</div>

</div>

<script src="/layout/Sortable.min.js"></script>

<script>
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

function addRow(event) {
	const addBtn = event.target;
	const listItem = addBtn.closest('.list-item');
	const container = listItem.parentElement;
	const newRow = listItem.cloneNode(true);

	newRow.querySelectorAll('input').forEach(input => input.value = '');
	newRow.querySelectorAll('select').forEach(select => select.selectedIndex = 0);

	container.appendChild(newRow);

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
</script>
