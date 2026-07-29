export async function createSnapshot(page, limit = 200) {
  const result = await page.evaluate((requestedLimit) => {
    const candidates = Array.from(document.querySelectorAll([
      "a[href]",
      "button",
      "input",
      "textarea",
      "select",
      "summary",
      "[role=button]",
      "[role=link]",
      "[role=checkbox]",
      "[role=radio]",
      "[role=tab]",
      "[contenteditable=true]",
      "[tabindex]",
    ].join(",")));

    function visible(element) {
      const style = getComputedStyle(element);
      const rect = element.getBoundingClientRect();
      return (
        style.display !== "none"
        && style.visibility !== "hidden"
        && rect.width > 0
        && rect.height > 0
      );
    }

    function cssEscape(value) {
      if (globalThis.CSS?.escape) return CSS.escape(value);
      return value.replace(/[^a-zA-Z0-9_-]/g, (char) => `\\${char}`);
    }

    function selectorFor(element) {
      if (element.id) return `#${cssEscape(element.id)}`;
      const testId = element.getAttribute("data-testid");
      if (testId) return `[data-testid="${testId.replaceAll('"', '\\"')}"]`;

      const segments = [];
      let node = element;
      while (node && node.nodeType === Node.ELEMENT_NODE && node !== document.body) {
        let segment = node.tagName.toLowerCase();
        const siblings = Array.from(node.parentElement?.children || [])
          .filter((sibling) => sibling.tagName === node.tagName);
        if (siblings.length > 1) {
          segment += `:nth-of-type(${siblings.indexOf(node) + 1})`;
        }
        segments.unshift(segment);
        node = node.parentElement;
      }
      return `body > ${segments.join(" > ")}`;
    }

    function roleFor(element) {
      const explicit = element.getAttribute("role");
      if (explicit) return explicit;
      const tag = element.tagName.toLowerCase();
      if (tag === "a") return "link";
      if (tag === "button" || tag === "summary") return "button";
      if (tag === "select") return "combobox";
      if (tag === "textarea") return "textbox";
      if (tag === "input") {
        const type = element.getAttribute("type") || "text";
        if (type === "checkbox") return "checkbox";
        if (type === "radio") return "radio";
        if (["button", "submit", "reset"].includes(type)) return "button";
        return "textbox";
      }
      return tag;
    }

    function nameFor(element) {
      const labelledBy = element.getAttribute("aria-labelledby");
      if (labelledBy) {
        const text = labelledBy
          .split(/\s+/)
          .map((id) => document.getElementById(id)?.textContent || "")
          .join(" ")
          .trim();
        if (text) return text;
      }
      const label = element.labels?.[0]?.textContent?.trim();
      return (
        element.getAttribute("aria-label")
        || label
        || element.getAttribute("placeholder")
        || element.getAttribute("title")
        || element.textContent?.trim()
        || element.getAttribute("value")
        || ""
      ).replace(/\s+/g, " ").slice(0, 240);
    }

    const elements = candidates
      .filter(visible)
      .slice(0, Math.max(1, Math.min(requestedLimit, 1000)))
      .map((element, index) => ({
        ref: `@e${index + 1}`,
        role: roleFor(element),
        name: nameFor(element),
        selector: selectorFor(element),
        disabled: Boolean(element.disabled),
        checked: typeof element.checked === "boolean" ? element.checked : undefined,
        value: "value" in element ? String(element.value).slice(0, 500) : undefined,
      }));

    return {
      title: document.title,
      url: location.href,
      text: document.body?.innerText?.slice(0, 50000) || "",
      elements,
    };
  }, limit);

  return result;
}
