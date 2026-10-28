// Page glue for the WebAssembly build: loads vector-feedback.wasm, provides the WebGL2
// binding (import module "gl"), a minimal WASI shim for the libc/libc++ runtime, and
// forwards pointer/keyboard input. `?selftest` runs the on-device selftest and reports
// the result in the DOM (#result) for headless evaluation.

const params = new URLSearchParams(location.search);
const canvas = document.getElementById("canvas");
const logEl = document.getElementById("log");
const resultEl = document.getElementById("result");

function appendLog(line) {
	if (logEl) logEl.textContent += line + "\n";
}

function setResult(status, text) {
	document.body.dataset.selftest = status;
	if (resultEl) resultEl.textContent = text;
}

window.addEventListener("error", (e) => {
	appendLog("error: " + e.message);
	setResult("fail", "SELFTEST FAIL: " + e.message);
});

const gl = canvas.getContext("webgl2", { antialias: false, alpha: false, preserveDrawingBuffer: false });

let memory = null;
const bytes = (ptr, len) => new Uint8Array(memory.buffer, ptr, len);
const decoder = new TextDecoder();
const encoder = new TextEncoder();
const str = (ptr, len) => decoder.decode(bytes(ptr, len));

// Integer handles <-> WebGL objects. 0 means "none".
const objects = [null];
function addObject(obj) {
	objects.push(obj);
	return objects.length - 1;
}
const obj = (id) => (id === 0 ? null : objects[id]);
function freeObject(id) {
	const o = objects[id];
	objects[id] = null;
	return o;
}
const uniforms = [null];

function writeLog(text, ptr, cap) {
	const encoded = encoder.encode(text || "").subarray(0, cap);
	bytes(ptr, encoded.length).set(encoded);
	return encoded.length;
}

const glImports = {
	createBuffer: () => addObject(gl.createBuffer()),
	createTexture: () => addObject(gl.createTexture()),
	createFramebuffer: () => addObject(gl.createFramebuffer()),
	createVertexArray: () => addObject(gl.createVertexArray()),
	deleteBuffer: (id) => gl.deleteBuffer(freeObject(id)),
	deleteTexture: (id) => gl.deleteTexture(freeObject(id)),
	deleteFramebuffer: (id) => gl.deleteFramebuffer(freeObject(id)),
	deleteVertexArray: (id) => gl.deleteVertexArray(freeObject(id)),
	createShader: (kind) => addObject(gl.createShader(kind)),
	deleteShader: (id) => gl.deleteShader(freeObject(id)),
	shaderSource: (id, ptr, len) => gl.shaderSource(obj(id), str(ptr, len)),
	compileShader: (id) => gl.compileShader(obj(id)),
	getShaderParameter: (id, pname) => Number(gl.getShaderParameter(obj(id), pname)),
	getShaderInfoLog: (id, ptr, cap) => writeLog(gl.getShaderInfoLog(obj(id)), ptr, cap),
	createProgram: () => addObject(gl.createProgram()),
	deleteProgram: (id) => gl.deleteProgram(freeObject(id)),
	attachShader: (p, s) => gl.attachShader(obj(p), obj(s)),
	linkProgram: (id) => gl.linkProgram(obj(id)),
	getProgramParameter: (id, pname) => Number(gl.getProgramParameter(obj(id), pname)),
	getProgramInfoLog: (id, ptr, cap) => writeLog(gl.getProgramInfoLog(obj(id)), ptr, cap),
	useProgram: (id) => gl.useProgram(obj(id)),
	getUniformLocation: (p, ptr, len) => {
		const loc = gl.getUniformLocation(obj(p), str(ptr, len));
		if (loc === null) return -1;
		uniforms.push(loc);
		return uniforms.length - 1;
	},
	uniform1i: (loc, v) => gl.uniform1i(uniforms[loc] ?? null, v),
	uniform1f: (loc, v) => gl.uniform1f(uniforms[loc] ?? null, v),
	uniformMatrix4fv: (loc, ptr) =>
		gl.uniformMatrix4fv(uniforms[loc] ?? null, false, new Float32Array(memory.buffer, ptr, 16)),
	bindBuffer: (target, id) => gl.bindBuffer(target, obj(id)),
	bufferData: (target, ptr, len, usage) => gl.bufferData(target, bytes(ptr, len), usage),
	bindVertexArray: (id) => gl.bindVertexArray(obj(id)),
	enableVertexAttribArray: (i) => gl.enableVertexAttribArray(i),
	vertexAttribPointer: (i, size, kind, norm, stride, offset) =>
		gl.vertexAttribPointer(i, size, kind, !!norm, stride, offset),
	bindTexture: (target, id) => gl.bindTexture(target, obj(id)),
	activeTexture: (unit) => gl.activeTexture(unit),
	texParameteri: (target, pname, v) => gl.texParameteri(target, pname, v),
	texImage2D: (target, level, internal, w, h, format, kind, ptr, len) => {
		let data = null;
		if (len > 0) {
			// Typed array views must match the pixel type in WebGL2.
			if (kind === gl.FLOAT) data = new Float32Array(memory.buffer, ptr, len / 4);
			else if (kind === gl.UNSIGNED_SHORT) data = new Uint16Array(memory.buffer, ptr, len / 2);
			else data = bytes(ptr, len);
		}
		gl.texImage2D(target, level, internal, w, h, 0, format, kind, data);
	},
	pixelStorei: (pname, v) => gl.pixelStorei(pname, v),
	bindFramebuffer: (target, id) => gl.bindFramebuffer(target, obj(id)),
	framebufferTexture2D: (target, att, textarget, tex, level) =>
		gl.framebufferTexture2D(target, att, textarget, obj(tex), level),
	checkFramebufferStatus: (target) => gl.checkFramebufferStatus(target),
	readPixels: (x, y, w, h, format, kind, ptr, len) => gl.readPixels(x, y, w, h, format, kind, bytes(ptr, len)),
	viewport: (x, y, w, h) => gl.viewport(x, y, w, h),
	clearColor: (r, g, b, a) => gl.clearColor(r, g, b, a),
	clear: (mask) => gl.clear(mask),
	enable: (cap) => gl.enable(cap),
	disable: (cap) => gl.disable(cap),
	blendFunc: (s, d) => gl.blendFunc(s, d),
	drawArrays: (mode, first, count) => gl.drawArrays(mode, first, count),
};

const levels = ["error", "warn", "info", "debug"];
const envImports = {
	now: () => performance.now() / 1000,
	canvasWidth: () => canvas.width,
	canvasHeight: () => canvas.height,
	cssHeight: () => canvas.clientHeight,
	setCanvasSize: (w, h) => {
		canvas.width = w;
		canvas.height = h;
	},
	log: (level, ptr, len) => {
		const line = `${levels[level] ?? "log"}: ${str(ptr, len)}`;
		(level === 0 ? console.error : console.log)(line);
		appendLog(line);
	},
};

// Just enough WASI for wasi-libc/libc++ start-up and stdio; everything else is ENOSYS.
class WasiExit extends Error {}
const ERRNO_SUCCESS = 0, ERRNO_BADF = 8, ERRNO_NOSYS = 52;
const stdio = ["", "", ""];
const wasiImports = {
	fd_write: (fd, iovs, iovsLen, nwrittenPtr) => {
		const view = new DataView(memory.buffer);
		let written = 0;
		for (let i = 0; i < iovsLen; i++) {
			const ptr = view.getUint32(iovs + i * 8, true);
			const len = view.getUint32(iovs + i * 8 + 4, true);
			if (fd === 1 || fd === 2) {
				stdio[fd] += str(ptr, len);
				let nl;
				while ((nl = stdio[fd].indexOf("\n")) >= 0) {
					appendLog(stdio[fd].slice(0, nl));
					console.log(stdio[fd].slice(0, nl));
					stdio[fd] = stdio[fd].slice(nl + 1);
				}
			}
			written += len;
		}
		view.setUint32(nwrittenPtr, written, true);
		return ERRNO_SUCCESS;
	},
	proc_exit: (code) => {
		throw new WasiExit(`wasm exited with code ${code}`);
	},
	random_get: (ptr, len) => {
		for (let off = 0; off < len; off += 65536) crypto.getRandomValues(bytes(ptr + off, Math.min(65536, len - off)));
		return ERRNO_SUCCESS;
	},
	clock_time_get: (_id, _precision, out) => {
		new DataView(memory.buffer).setBigUint64(out, BigInt(Math.round(performance.now() * 1e6)), true);
		return ERRNO_SUCCESS;
	},
	environ_sizes_get: (countPtr, sizePtr) => {
		const view = new DataView(memory.buffer);
		view.setUint32(countPtr, 0, true);
		view.setUint32(sizePtr, 0, true);
		return ERRNO_SUCCESS;
	},
	environ_get: () => ERRNO_SUCCESS,
	args_sizes_get: (countPtr, sizePtr) => wasiImports.environ_sizes_get(countPtr, sizePtr),
	args_get: () => ERRNO_SUCCESS,
	fd_prestat_get: () => ERRNO_BADF,
	fd_close: () => ERRNO_SUCCESS,
};

function buildImports(module) {
	const imports = { gl: glImports, env: envImports, wasi_snapshot_preview1: {} };
	for (const imp of WebAssembly.Module.imports(module)) {
		const ns = (imports[imp.module] ??= {});
		if (imp.module === "wasi_snapshot_preview1") {
			ns[imp.name] = wasiImports[imp.name] ?? (() => ERRNO_NOSYS);
		} else if (!(imp.name in ns)) {
			throw new Error(`missing import ${imp.module}.${imp.name}`);
		}
	}
	return imports;
}

// KeyboardEvent.code -> GLFW key code (see src/keymap.zig).
function glfwKey(code) {
	let m;
	if ((m = /^Key([A-Z])$/.exec(code))) return m[1].charCodeAt(0);
	if ((m = /^Digit([0-9])$/.exec(code))) return 48 + Number(m[1]);
	if ((m = /^Numpad([0-9])$/.exec(code))) return 320 + Number(m[1]);
	return {
		Space: 32, Comma: 44, Minus: 45, Period: 46, Equal: 61,
		BracketLeft: 91, BracketRight: 93, Escape: 256, Tab: 258,
		ArrowRight: 262, ArrowLeft: 263, ArrowDown: 264, ArrowUp: 265,
		F1: 290, NumpadSubtract: 333, NumpadAdd: 334,
	}[code] ?? -1;
}

function fitCanvas() {
	const dpr = window.devicePixelRatio || 1;
	const w = Math.max(1, Math.round(canvas.clientWidth * dpr));
	const h = Math.max(1, Math.round(canvas.clientHeight * dpr));
	if (canvas.width !== w || canvas.height !== h) {
		canvas.width = w;
		canvas.height = h;
	}
}

function attachInput(ex) {
	canvas.addEventListener("contextmenu", (e) => e.preventDefault());
	canvas.addEventListener("pointerdown", (e) => {
		canvas.focus();
		canvas.setPointerCapture(e.pointerId);
		ex.vf_cursor(e.offsetX, e.offsetY);
		ex.vf_mouse_button(e.button, 1, e.shiftKey || e.ctrlKey ? 1 : 0);
		e.preventDefault();
	});
	canvas.addEventListener("pointerup", (e) => ex.vf_mouse_button(e.button, 0, 0));
	canvas.addEventListener("pointermove", (e) => ex.vf_cursor(e.offsetX, e.offsetY));
	canvas.addEventListener(
		"wheel",
		(e) => {
			const scale = e.deltaMode === 1 ? 1 / 3 : e.deltaMode === 2 ? 3 : 1 / 100;
			ex.vf_scroll(-e.deltaY * scale);
			e.preventDefault();
		},
		{ passive: false },
	);
	const onKey = (down) => (e) => {
		const key = glfwKey(e.code);
		if (key < 0 || e.metaKey || e.altKey) return;
		if (!e.ctrlKey) e.preventDefault();
		if (down && e.repeat) return;
		ex.vf_key(key, down ? 1 : 0);
	};
	window.addEventListener("keydown", onKey(true));
	window.addEventListener("keyup", onKey(false));
	window.addEventListener("blur", () => {
		for (let k = 0; k < 335; k++) ex.vf_key(k, 0);
	});
}

async function main() {
	if (!gl) throw new Error("WebGL2 is not available");
	// Rendering into the RGBA16F feedback buffers needs float colour attachments.
	if (!gl.getExtension("EXT_color_buffer_float") && !gl.getExtension("EXT_color_buffer_half_float")) {
		throw new Error("EXT_color_buffer_float is not available");
	}
	appendLog(`info: ${gl.getParameter(gl.VERSION)} / ${gl.getParameter(gl.SHADING_LANGUAGE_VERSION)}`);

	const response = await fetch("vector-feedback.wasm");
	const module = await WebAssembly.compileStreaming(response);
	const instance = await WebAssembly.instantiate(module, buildImports(module));
	const ex = instance.exports;
	memory = ex.memory;
	ex._initialize?.();

	fitCanvas();
	if (ex.vf_init() !== 0) throw new Error("vf_init failed");
	attachInput(ex);
	// Optional ?seed=N (0-4) picks the initial seed shape via its key binding.
	const seed = params.get("seed");
	if (seed !== null && /^[0-4]$/.test(seed)) {
		ex.vf_key(48 + Number(seed), 1);
		ex.vf_key(48 + Number(seed), 0);
	}

	const selftestFrames = params.has("selftest") ? Number(params.get("selftest")) || 120 : 0;
	let frames = 0;
	await new Promise((resolve, reject) => {
		const tick = () => {
			try {
				if (!selftestFrames) fitCanvas();
				if (ex.vf_frame() !== 0) throw new Error("vf_frame failed");
				frames++;
				if (selftestFrames && frames === selftestFrames) {
					const failed = ex.vf_selftest() !== 0;
					setResult(failed ? "fail" : "pass", failed ? "SELFTEST FAIL" : "SELFTEST PASS");
					resolve();
					return;
				}
			} catch (e) {
				reject(e);
				return;
			}
			requestAnimationFrame(tick);
		};
		requestAnimationFrame(tick);
	});
}

// Top-level await: in selftest mode the module (and so the document's load event, which
// headless `--dump-dom` waits for) only completes once the verdict is in the DOM.
try {
	await main();
} catch (e) {
	appendLog("error: " + (e && e.message ? e.message : e));
	setResult("fail", "SELFTEST FAIL: " + (e && e.message ? e.message : e));
	console.error(e);
}
