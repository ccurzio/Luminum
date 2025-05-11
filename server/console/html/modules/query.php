<div class="content">
	<h1>Luminum Query</h1>

<div>
	<div class="module-content" style="display: flex; justify-content: space-between; align-items: flex-start;">
		<div class="main-content">
			<p style="margin-top: 10px;">
			<span style="font-size: 20px; font-weight: bold;">I want to retrieve:</span>
			</p>
			<div id="get-list">
				<div class="list-item"><img src="images/reorder-dis.png" class="drag-handle"> <input type="text" placeholder="Sensor"> <img src="images/add.png" class="add"></div>
				<br>
			</div>

			<hr>

			<p style="margin-top: 20px;">
			<span style="font-size: 20px; font-weight: bold;">From</span> <select style="font-size: 15px; height: 30px; margin-left: 2px;" name="targets" id="targets" class="target-dropdown" onchange="selectSuffix();"><option name="matching" value="matching" default="default">endpoints matching</option><option name="all" value="all">all machines</option></select> <span id="tsuffix" style="font-size: 20px; font-weight: bold;">:</span>
			</p>
			<div id="from-list">
				<div class="list-item"><img src="images/reorder-dis.png" class="drag-handle"> <input type="text" placeholder="Sensor"> <select class="row-dropdown" style="font-size: 15px; height: 30px;" name="fromop"><option name="equals" value="equals">equals</option><option name="notequals" value="notequals">not equals</option><option name="contains" value="contains">contains</option><option name="greaterthan" value="greaterthan">greater than</option><option name="lessthan" value="lessthan">less than</option></select> <input type="text" placeholder="Value"> <img src="images/add.png" class="add"></div>
				<br>
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

function updateListControls(containerId) {
	//const listItems = document.querySelectorAll(#${containerId} .list-item);
	const container = document.getElementById(containerId);

	// Store dropdown values associated with each list-item
	const savedDropdownValues = [];

	const children = Array.from(container.children);
	for (let i = 0; i < children.length - 1; i++) {
		const current = children[i];
		const next = children[i + 1];
		if (current.classList.contains("list-item") && next && next.querySelector("select.logic-dropdown")) {
			savedDropdownValues.push(next.querySelector("select.logic-dropdown").value);
		}
	}

	// Remove all old logic-dropdown wrappers
	container.querySelectorAll(".logic-dropdown").forEach(dropdown => {
		const wrapper = dropdown.closest("div");
		if (wrapper && wrapper.parentNode === container) wrapper.remove();
	});

	// Remove all old dropdowns
	const listItems = container.querySelectorAll(".list-item");
	const allItems = container.querySelectorAll(".list-item");

	listItems.forEach((item, index) => {
		const addBtn = item.querySelector('.add');

		// Show add button only on the last row
		addBtn.style.display = index === listItems.length - 1 ? "inline" : "none";

		// Manage remove button
		let removeBtn = item.querySelector('.remove');

		if (index === 0) {
			// Always remove from the top row
			if (removeBtn) removeBtn.remove();
			}
		else {
			// Add remove button if missing
			if (!removeBtn) {
				removeBtn = document.createElement("img");
				removeBtn.src = "images/remove.png";
				removeBtn.className = "remove";
				removeBtn.style.cursor = "pointer";
				removeBtn.style.marginLeft = "4px"; // Adjust as needed
				addBtn.insertAdjacentElement("beforebegin", removeBtn);
				}
    			}

		if (containerId === "from-list") {
			// Add dropdown between rows if more than 1 item and not last
			if (index < listItems.length - 1) {
				const logicWrapper = document.createElement("div");
				logicWrapper.style.display = "flex";
				logicWrapper.style.alignItems = "center";

					const dropdown = document.createElement("select");
					dropdown.className = "logic-dropdown";
					dropdown.style.display = "block";
					dropdown.style.width = "60px";
					dropdown.style.height = "30px";
					dropdown.style.marginTop = "5px";
					dropdown.style.marginLeft = "30px";

					// Add options as needed
					dropdown.innerHTML = `
						<option value="and">AND</option>
						<option value="or">OR</option>
						`;
					//dropdown.value = savedDropdownValues[index] || "and";
					const id = item.dataset.id;
					dropdown.value = savedDropdownValues[id] || "and";

					const image = document.createElement("img");
					image.src = "icons/addgroup.png";
					image.className = "logic-dropdown";
					image.style.height = "24px";
					image.style.width = "24px";
					image.style.marginTop = "5px";
					image.style.marginLeft = "5px";
					image.style.cursor = "pointer";

					// Insert after this item
					logicWrapper.appendChild(dropdown);
					logicWrapper.appendChild(image);
					item.insertAdjacentElement("afterend", logicWrapper);
				}
			}
		});

	const reorderImages = document.querySelectorAll(`#${containerId} .drag-handle`);
	reorderImages.forEach(img => {
		if (listItems.length > 1) {
			img.src = "images/reorder.png";
			img.classList.remove("disabled");
			img.style.opacity = "1.0";
		} else {
			img.src = "images/reorder-dis.png";
			img.classList.add("disabled");
			img.style.opacity = "0";
		}
	});
}

// Handle addgroup / collapsegroup toggle
document.addEventListener("click", function (event) {
if (event.target.tagName === "IMG" && event.target.classList.contains("logic-dropdown") && event.target.src.includes("addgroup.png")) {
	const clickedWrapper = event.target.closest("div"); // the wrapper div with dropdown + image
	const container = clickedWrapper.parentNode;

	// Get all items after the wrapper
	const allItems = Array.from(container.children);
	const wrapperIndex = allItems.indexOf(clickedWrapper);

	// Extract everything after the wrapper
	const itemsToMove = allItems.slice(wrapperIndex + 1);

	// Create the group wrapper
	const groupDiv = document.createElement("div");
	groupDiv.className = "group-wrapper";
	groupDiv.style.marginLeft = "30px"; // or however you'd like to indent it
	groupDiv.style.borderLeft = "5px solid #aaa";
	groupDiv.style.paddingLeft = "10px";
	groupDiv.style.marginTop = "5px";

	// Move elements into the new group div
	itemsToMove.forEach(item => groupDiv.appendChild(item));

	// Insert the group div right after the clicked wrapper
	container.insertBefore(groupDiv, container.children[wrapperIndex + 1]);

	updateListControls("get-list");
	updateListControls("from-list");
	}

	if (event.target.classList.contains("add")) {
		const currentItem = event.target.closest(".list-item");
		const container = currentItem.parentNode;
		const clone = currentItem.cloneNode(true);
		const input = clone.querySelector("input");

		if (input) input.value = "";
		clone.dataset.id = Date.now().toString() + Math.random().toString(36).substr(2, 5);

		// Remove any old remove button from the clone (in case it’s copied from a row that had one)
		const oldRemove = clone.querySelector(".remove");
		if (oldRemove) oldRemove.remove();
		container.insertBefore(clone, currentItem.nextSibling);

		// Update both lists in case needed
		updateListControls("get-list");
		updateListControls("from-list");
		}

	if (event.target.classList.contains("remove")) {
		const currentItem = event.target.closest(".list-item");
		const container = currentItem.parentNode;
		const nextElem = currentItem.nextElementSibling;
		if (nextElem && nextElem.classList.contains("logic-wrapper")) { nextElem.remove(); }
		currentItem.remove();
		updateListControls("get-list");
		updateListControls("from-list");
  		}
	});

function initSortable(containerId) {
	new Sortable(document.getElementById(containerId), {
		handle: '.drag-handle',
		animation: 150,
		ghostClass: 'ghost-hidden',
		onMove: function (evt) { return !evt.related.classList.contains('disabled'); },
		onEnd: () => { updateListControls(containerId); }
		}
	);
}

// Initial setup
document.addEventListener("DOMContentLoaded", () => {
	// Assign data-id to existing items
	document.querySelectorAll(".list-item").forEach(item => {
		if (!item.dataset.id) {
			item.dataset.id = Date.now().toString() + Math.random().toString(36).substr(2, 5);
		}
	});

	updateListControls("get-list");
	updateListControls("from-list");
	initSortable("get-list");
	initSortable("from-list");
});
</script>
