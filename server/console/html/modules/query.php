<div class="content">
	<h1>Luminum Query</h1>

<div>
	<div class="module-content" style="display: flex; justify-content: space-between; align-items: flex-start;">
		<div class="main-content">
			<p style="margin-top: 10px;">
			<span style="font-size: 20px; font-weight: bold;">I want to retrieve:</span>
			</p>
			<div id="get-list">
				<div class="list-item" style="margin-bottom: 5px;"><img src="images/reorder-dis.png" class="drag-handle" style="vertical-align: middle"> <input type="text" placeholder="Sensor"> <img src="images/add.png" class="add" style="vertical-align: middle"></div>
			</div>

			<p style="margin-top: 20px;">
			<span style="font-size: 20px; font-weight: bold;">From</span> <select style="font-size: 15px; height: 30px; margin-left: 2px;" name="targets" id="targets" class="target-dropdown" onchange="selectSuffix();"><option name="matching" value="matching" default="default">endpoints matching</option><option name="all" value="all">all endpoints</option></select> <span id="tsuffix" style="font-size: 20px; font-weight: bold;">:</span>
			</p>
			<div id="from-list">
				<div class="list-item"><img src="images/reorder-dis.png" class="drag-handle" style="vertical-align: middle;"> <input type="text" placeholder="Sensor"> <select class="row-dropdown" style="font-size: 15px; height: 30px;" name="fromop"><option name="equals" value="equals">equals</option><option name="notequals" value="notequals">not equals</option><option name="contains" value="contains">contains</option><option name="greaterthan" value="greaterthan">greater than</option><option name="lessthan" value="lessthan">less than</option></select> <input type="text" placeholder="Value"> <img src="images/add.png" class="add" style="vertical-align: middle;"></div>
			</div>
		</div>
		<div class="right-box">
			<span style="font-weight: bold">Question Summary:</span><br>
			<p>
			</p>
		</div>
	</div>
	<div style="width: 100%; text-align: right; padding-top: 10px;">
		<button class="formgo" style="margin-right: 0;">Submit Query</button> <button class="formgo" style="margin-left: 0;">Reset Form</button>
	</div>

</div>

<script src="/layout/Sortable.min.js"></script>

<script>
function addRow(event) {
  const addBtn = event.target;
  const listItem = addBtn.closest('.list-item');
  const container = listItem.parentElement;

  // Clone the list-item
  const newRow = listItem.cloneNode(true);

  // Clear input values inside the clone
  newRow.querySelectorAll('input').forEach(input => input.value = '');
  newRow.querySelectorAll('select').forEach(select => select.selectedIndex = 0);

  // Append the new row
  container.appendChild(newRow);

  updateRemoveButtons(container);
  updateDragHandleIcons(container);
  attachHandlers();

  // Insert logical operators only in #from-list
  if (container.id === 'from-list') {
    insertLogicalOperators(container);
  }
}

function removeRow(event) {
  const listItem = event.target.closest('.list-item');
  const container = listItem.parentElement;
  listItem.remove();

  updateRemoveButtons(container);
  updateDragHandleIcons(container);
  attachHandlers();

  // Insert logical operators only in #from-list
  if (container.id === 'from-list') {
    insertLogicalOperators(container);
  }
}
  function updateRemoveButtons(container) {
    const rows = container.querySelectorAll('.list-item');
    rows.forEach((row, index) => {
      // Remove any existing remove buttons
      const existingRemove = row.querySelector('.remove');
      if (existingRemove) existingRemove.remove();

      // Only add a remove button if it's not the first row
      if (index > 0) {
        const removeBtn = document.createElement('img');
        removeBtn.src = 'images/remove.png';
        removeBtn.className = 'remove';
        removeBtn.style.cursor = 'pointer';
        removeBtn.style.marginRight = '8px';
	removeBtn.style.verticalAlign = 'middle';

        // Insert before the add button
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

  // Initialize on page load
  window.addEventListener('DOMContentLoaded', () => {
    // Apply remove buttons to both lists
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
	      dragHandle.src = `images/${dragIcon}`;
		}
	else {
		dragHandle.style.opacity = 0
		dragHandle.src = 'images/reorder-dis.png';
		}
    }
  });
}

function insertLogicalOperators(container) {
	container.querySelectorAll('.logical-operator, .logical-operator-br').forEach(el => el.remove());
  const rows = Array.from(container.querySelectorAll('.list-item'));

  // Insert dropdown between each pair of rows (not after the last one)
	for (let i = 0; i < rows.length - 1; i++) {
	const row = rows[i];
    const select = document.createElement('select');
	const br = document.createElement('br');
	br.className = 'logical-operator-br';

    select.className = 'logical-operator';
    select.style.width = '75px';
    select.style.margin = '5px 0 5px 30px';
    select.style.fontSize = '15px';
    select.style.height = '30px';

    const andOption = new Option('AND', 'AND');
    const orOption = new Option('OR', 'OR');
    select.add(andOption);
    select.add(orOption);

	row.appendChild(br);
	row.appendChild(select);

	//rows[i].after(select);
  }
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

    new Sortable(container, {
      handle: '.drag-handle',
      animation: 150,

      onStart: function (evt) {
        evt.item.classList.add('hidden-during-drag');
      },

      onEnd: function (evt) {
        evt.item.classList.remove('hidden-during-drag');

        // Update remove buttons and drag handle icons after reorder
        updateRemoveButtons(container);
        updateDragHandleIcons(container);
        attachHandlers(); // reattach event listeners for remove buttons
	if (container.id === 'from-list') { insertLogicalOperators(container); }
      }
    });
  });
}

</script>
