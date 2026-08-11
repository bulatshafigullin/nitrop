// Nitro.Live client-side patch adapter.
//
// Wraps vendored morphdom (github:SteffenDE/morphdom, the same fork Phoenix
// LiveView depends on) so a live-view update patches the existing DOM in
// place instead of the outerHTML full-replace nitro:update/2 does today.
//
// The onBeforeElUpdated focus-preservation logic below is adapted (heavily
// trimmed) from Phoenix LiveView's assets/js/phoenix_live_view/dom_patch.ts
// and dom.ts (mergeAttrs / mergeFocusedInput / restoreFocus / isEditableInput).
// Everything specific to Phoenix's LiveComponents, streams, portals and
// ref-locking was dropped -- nitro has none of those concepts, only a
// single-level live view per patch call.
import morphdom from "./vendor/morphdom/index.js";

const FOCUSABLE_INPUTS = [
  "text", "textarea", "number", "email", "password", "search",
  "tel", "url", "date", "datetime-local", "time", "month", "week",
];

function isTextualInput(el) {
  return !!el && FOCUSABLE_INPUTS.indexOf(el.type) >= 0;
}

function hasSelectionRange(el) {
  return !!el && typeof el.setSelectionRange === "function" &&
    (el.type === "text" || el.type === "textarea");
}

function isEditableInput(el) {
  return !!el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.tagName === "SELECT") &&
    !(el.tagName === "INPUT" && el.type === "button");
}

function isIgnored(el) {
  return !!(el.getAttribute && el.getAttribute("data-nitro-ignore") !== null);
}

// Copies toEl's attributes onto fromEl, dropping ones toEl no longer has.
function mergeAttrs(target, source, exclude) {
  const excludeSet = new Set(exclude || []);
  const sourceAttrs = source.attributes;
  for (let i = sourceAttrs.length - 1; i >= 0; i--) {
    const name = sourceAttrs[i].name;
    if (!excludeSet.has(name)) {
      const value = source.getAttribute(name);
      if (target.getAttribute(name) !== value) target.setAttribute(name, value);
    }
  }
  const targetAttrs = target.attributes;
  for (let i = targetAttrs.length - 1; i >= 0; i--) {
    const name = targetAttrs[i].name;
    if (!excludeSet.has(name) && !source.hasAttribute(name)) target.removeAttribute(name);
  }
}

// Applies everything except `value` so the user's in-progress typing survives
// a patch that arrived while they were still editing the field.
function mergeFocusedInput(target, source) {
  if (target.tagName !== "SELECT") mergeAttrs(target, source, ["value"]);
  if (source.readOnly) target.setAttribute("readonly", "");
  else target.removeAttribute("readonly");
}

function restoreFocus(focused, selectionStart, selectionEnd) {
  if (!focused || !document.body.contains(focused)) return;
  if (!isTextualInput(focused) && focused.tagName !== "SELECT") return;
  if (document.activeElement !== focused) focused.focus();
  if (hasSelectionRange(focused) && selectionStart != null) {
    focused.setSelectionRange(selectionStart, selectionEnd);
  }
}

function parse(html) {
  const tpl = document.createElement("template");
  tpl.innerHTML = html.trim();
  return tpl.content.firstElementChild;
}

const NitroLive = {
  // Patches the element with id `id` in place to match `html`, preserving
  // focus/selection and in-progress input on whichever field the user is
  // currently editing inside it.
  patch(id, html) {
    const container = document.getElementById(id);
    const newTree = parse(html);
    if (!container || !newTree) return;

    const focused = document.activeElement;
    const focusedWithin = !!focused && container.contains(focused);
    const selectionStart = focusedWithin && hasSelectionRange(focused) ? focused.selectionStart : null;
    const selectionEnd = focusedWithin && hasSelectionRange(focused) ? focused.selectionEnd : null;

    morphdom(container, newTree, {
      onBeforeElUpdated(fromEl, toEl) {
        if (isIgnored(fromEl)) return false;

        const isFocusedEditable = focusedWithin && fromEl.isSameNode(focused) && isEditableInput(fromEl);
        if (isFocusedEditable && fromEl.type !== "hidden") {
          mergeFocusedInput(fromEl, toEl);
          return false;
        }
        return true;
      },
    });

    if (focusedWithin) restoreFocus(focused, selectionStart, selectionEnd);
  },
};

if (typeof window !== "undefined") window.NitroLive = NitroLive;
export default NitroLive;
