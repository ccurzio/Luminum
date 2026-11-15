//
// LuminumOverlay / LuminumSession — the console's forced-focus popup and
// inactivity timeout client.
//
// LuminumOverlay dims the whole page and shows a popup with a customizable
// title, message, and buttons (see the #overlay markup in layout/header.php
// and the #overlay/.overlay-popup rules in layout/default.css).
//
// LuminumSession drives the inactivity timeout. The server owns the deadline
// (AUTH.SESSION.EXPIRES, set to now() + UTIMEOUT at login and on each
// refresh); the client tracks user activity, keeps the server deadline in
// step via /api/touch.php while the user is active, shows the 2-minute
// warning, and logs the user out at the deadline. Background page activity
// (e.g. the Client Status table polling the API) never counts as activity —
// only real user input does, and the polling endpoints never refresh the
// deadline server-side either.
//
'use strict';

var LuminumOverlay = {
	showing: false,

	// opts: { title, message, buttons: [{ label, onclick }] }
	show: function (opts) {
		var overlay = document.getElementById('overlay');
		if (!overlay) { return; }
		document.getElementById('overlay-title').textContent = opts.title || '';
		document.getElementById('overlay-message').textContent = opts.message || '';
		var box = document.getElementById('overlay-buttons');
		box.innerHTML = '';
		(opts.buttons || []).forEach(function (btn, i) {
			var b = document.createElement('button');
			b.className = 'formgo';
			b.style.marginLeft = '0';
			b.style.marginRight = '0';
			if (i > 0) { b.style.marginLeft = '10px'; }
			b.textContent = btn.label;
			b.addEventListener('click', function (e) {
				e.stopPropagation();
				if (btn.onclick) { btn.onclick(); }
			});
			box.appendChild(b);
		});
		overlay.style.display = 'block';
		this.showing = true;
	},

	hide: function () {
		var overlay = document.getElementById('overlay');
		if (overlay) { overlay.style.display = 'none'; }
		this.showing = false;
	}
};

var LuminumSession = {
	WARN_SECONDS: 120,      // the "2 minute warning"
	TOUCH_THROTTLE_MS: 30000,

	cfg: null,
	deadline: 0,            // Unix seconds, server clock
	offset: 0,              // server clock - local clock, in seconds
	lastTouch: 0,
	warnShown: false,

	// cfg: { deadline, timeout, warn, serverNow } — injected by footer.php
	init: function (cfg) {
		this.cfg = cfg;
		this.deadline = cfg.deadline;
		this.offset = cfg.serverNow - Date.now() / 1000;
		var self = this;
		['mousemove', 'mousedown', 'keydown', 'scroll', 'touchstart', 'wheel'].forEach(function (evt) {
			document.addEventListener(evt, function () { self.onActivity(); }, { passive: true });
		});
		setInterval(function () { self.tick(); }, 1000);
		this.tick();
	},

	// Current time on the server clock (compensates for clock skew).
	now: function () { return Date.now() / 1000 + this.offset; },

	remaining: function () { return this.deadline - this.now(); },

	onActivity: function () {
		if (this.warnShown) {
			// The user is back: dismiss the warning and renew the session.
			this.hideWarning();
			this.touch(true);
			return;
		}
		// Keep the server deadline in step while the user is active: once the
		// window has run down past the warning margin, a refresh is due.
		if (this.remaining() < this.cfg.timeout - this.WARN_SECONDS) {
			this.touch();
		}
	},

	// Refresh the server deadline via /api/touch.php. Throttled, unless
	// force is set (explicit Extend / warning dismissal).
	touch: function (force) {
		var nowMs = Date.now();
		if (!force && nowMs - this.lastTouch < this.TOUCH_THROTTLE_MS) { return; }
		this.lastTouch = nowMs;
		var self = this;
		fetch('/api/touch.php', { credentials: 'same-origin' })
			.then(function (r) { return r.ok ? r.json() : null; })
			.then(function (data) {
				if (data && data.expires) {
					self.deadline = data.expires;
					self.offset = data.now - Date.now() / 1000;
				}
			})
			.catch(function () { /* keep the current deadline; the server enforces it anyway */ });
	},

	showWarning: function () {
		var self = this;
		this.warnShown = true;
		LuminumOverlay.show({
			title: 'Session Timeout',
			message: 'Your session is about to time out due to inactivity, at which point you will automatically be logged out. You may click "extend" to renew your session, or you can manually log out.',
			buttons: [
				{ label: 'Extend', onclick: function () { self.hideWarning(); self.touch(true); } },
				{ label: 'Log Out', onclick: function () { self.logout(); } }
			]
		});
	},

	hideWarning: function () {
		this.warnShown = false;
		LuminumOverlay.hide();
	},

	logout: function () {
		window.location.href = '/index.php?logout=1';
	},

	tick: function () {
		var rem = this.remaining();
		if (rem <= 0) {
			this.logout();
			return;
		}
		// No warning when the whole window is shorter than the warning itself.
		if (this.cfg.warn && this.cfg.timeout > this.WARN_SECONDS && !this.warnShown && rem <= this.WARN_SECONDS) {
			this.showWarning();
		}
	}
};
