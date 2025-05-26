<div class="content">
	<h1>Luminum Query</h1>

<div>
	<div class="module-content" style="display: flex; justify-content: space-between; align-items: flex-start;">
		<div class="main-content">
			<p style="margin-top: 10px;">
			<span style="font-size: 20px; font-weight: bold;">I want to retrieve:</span>
			</p>
			<div id="get-list">
				<div class="list-item" style="margin-bottom: 5px;"><img src="icons/reorder-dis.png" class="drag-handle" style="vertical-align: middle"> <input type="text" placeholder="Sensor"> <img src="icons/add.png" class="add" style="vertical-align: middle; margin-bottom: 3px;"></div>
			</div>

			<p style="margin-top: 20px;">
			<span style="font-size: 20px; font-weight: bold;">From</span> <select style="font-size: 15px; height: 30px; margin-left: 2px;" name="targets" id="targets" class="target-dropdown" onchange="selectSuffix();"><option name="matching" value="matching" default="default">endpoints matching</option><option name="all" value="all">all endpoints</option></select> <span id="tsuffix" style="font-size: 20px; font-weight: bold;">:</span>
			</p>
			<div id="from-list">
				<div class="list-item"><img src="icons/reorder-dis.png" class="drag-handle" style="vertical-align: middle;"> <input type="text" placeholder="Sensor"> <select class="row-dropdown" style="font-size: 15px; height: 30px;" name="fromop"><option name="equals" value="equals">equals</option><option name="notequals" value="notequals">not equals</option><option name="contains" value="contains">contains</option><option name="greaterthan" value="greaterthan">greater than</option><option name="lessthan" value="lessthan">less than</option></select> <input type="text" placeholder="Value"> <img src="icons/add.png" class="add" style="vertical-align: middle; margin-bottom: 3px;"></div>
			</div>
		</div>
		<div class="right-box">
			<span style="font-weight: bold">Question Summary:</span><br>
			<p>
			</p>
		</div>
	</div>
	<div style="width: 100%; text-align: right; padding-top: 10px;">
		<button id="querygo" class="formgo" style="margin-right: 0;" disabled="disabled">Submit Query</button> <button class="formgo" style="margin-left: 0;">Reset Form</button>
	</div>

</div>

<script src="/layout/Sortable.min.js"></script>

<script>
function addRow(event) {
	const addBtn = event.target;
	const listItem = addBtn.closest('.list-item');
	const container = listItem.parentElement;
	const newRow = listItem.cloneNode(true);

	newRow.querySelectorAll('input').forEach(input => input.value = '');
	newRow.querySelectorAll('select').forEach(select => select.selectedIndex = 0);

	container.appendChild(newRow);

	updateRemoveButtons(container);
	updateDragHandleIcons(container);
	attachHandlers();

	//if (container.id === 'from-list') { insertLogicalOperators(container); }
	if (container.closest('#from-list')) {
		const rootContainer = container.classList.contains('group-container') ? container : document.getElementById('from-list');
		insertLogicalOperators(rootContainer);
		}
	}

function removeRow(event) {
	const listItem = event.target.closest('.list-item');
	const container = listItem.parentElement;
	listItem.remove();

	updateRemoveButtons(container);
	updateDragHandleIcons(container);
	attachHandlers();

	//if (container.id === 'from-list') { insertLogicalOperators(container); }
	if (container.closest('#from-list')) {
		const rootContainer = container.classList.contains('group-container') ? container : document.getElementById('from-list');
		insertLogicalOperators(rootContainer);
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
	document.querySelectorAll('.add').forEach(addBtn => {
		addBtn.removeEventListener('click', addRow);
		addBtn.addEventListener('click', addRow);
		});

	document.querySelectorAll('.remove').forEach(removeBtn => {
		removeBtn.removeEventListener('click', removeRow);
		removeBtn.addEventListener('click', removeRow);
		});
	}

window.addEventListener('DOMContentLoaded', () => {
	updateRemoveButtons(document.getElementById('get-list'));
	updateRemoveButtons(document.getElementById('from-list'));
	updateDragHandleIcons(document.getElementById('get-list'));
	updateDragHandleIcons(document.getElementById('from-list'));
	attachHandlers();
	initSortable();
	});

function updateDragHandleIcons(container) {
	const rows = container.querySelectorAll('.list-item');
	const dragIcon = rows.length > 1 ? 'reorder.png' : 'reorder-dis.png';

	rows.forEach(row => {
		const dragHandle = row.querySelector('.drag-handle');
		if (dragHandle) {
			if (rows.length > 1) {
				dragHandle.style.opacity = 1;
				dragHandle.src = `icons/${dragIcon}`;
				}
			else {
				dragHandle.style.opacity = 0
				dragHandle.src = 'icons/reorder-dis.png';
				}
			}
		});
	}

function insertLogicalOperators(container) {
	// Clear existing operators and group buttons
	container.querySelectorAll('.logical-operator, .logical-operator-br, .group-button').forEach(el => el.remove());

	// Helper function to insert operators between rows
	function processRows(rowContainer) {
		const rows = Array.from(rowContainer.querySelectorAll(':scope > .list-item'));

		for (let i = 0; i < rows.length - 1; i++) {
			const row = rows[i];

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
			groupImg.src = 'icons/addgroup.png';
			groupImg.className = 'group-button';
			groupImg.style.width = '24px';
			groupImg.style.height = '24px';
			groupImg.style.marginBottom = '3px';
			groupImg.style.cursor = 'pointer';
			groupImg.style.marginLeft = '8px';
			groupImg.style.verticalAlign = 'middle';
			groupImg.addEventListener('click', toggleGroup);

			row.appendChild(br);
			row.appendChild(select);
			row.appendChild(groupImg);
		}
	}

	// Process top-level rows
	processRows(container);

	// Process each group individually
	container.querySelectorAll('.group-container').forEach(group => {
		processRows(group);
	});
}

function toggleGroup(event) {
	const groupIcon = event.target;
	const row = groupIcon.closest('.list-item');

	if (groupIcon.src.includes('addgroup.png')) {
		// Start grouping
		const nextRows = [];
		let sibling = row.nextElementSibling;

		while (sibling && sibling.classList.contains('list-item') && !sibling.querySelector('.logical-operator')) {
			nextRows.push(sibling);
			sibling = sibling.nextElementSibling;
		}

		if (nextRows.length === 0) return;

		const groupContainer = document.createElement('div');
		groupContainer.className = 'group-container';
		groupContainer.style.marginLeft = '100px';
		groupContainer.style.borderLeft = '4px solid #aaa';
		groupContainer.style.paddingLeft = '10px';

		nextRows.forEach(r => groupContainer.appendChild(r));
		row.after(groupContainer);

		groupIcon.src = 'icons/collapsegroup.png';

	} else {
		// Ungroup
		const groupContainer = row.nextElementSibling;
		if (groupContainer && groupContainer.classList.contains('group-container')) {
			while (groupContainer.firstChild) {
				row.after(groupContainer.firstChild);
			}
			groupContainer.remove();
		}

		groupIcon.src = 'icons/addgroup.png';
	}
initSortable();
}

function selectSuffix() {
	var val = document.getElementById("targets").value;

	if (val == "all") {
		document.getElementById("tsuffix").textContent = "";
		document.getElementById("from-list").style.opacity = "0";
		}
	else { document.getElementById("tsuffix").textContent = ":";
		document.getElementById("from-list").style.opacity = "1";
		}
	}

function initSortable() {
	['get-list', 'from-list'].forEach(id => {
		const container = document.getElementById(id);

		// Init sortable for main container
		new Sortable(container, {
			handle: '.drag-handle',
			animation: 150,
			filter: '.group-container',
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
					updateRemoveButtons(group);
					updateDragHandleIcons(group);
					attachHandlers();
				}
			});
		});
	});
}
</script>
