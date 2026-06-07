// Guard against double-load (auto-includes + explicit <script> both firing).
if (window.__deadfinderSearchLoaded) {
  // already wired up
} else {
  window.__deadfinderSearchLoaded = true;

  if (typeof Fuse === "undefined") {
    const script = document.createElement("script");
    script.src = "https://cdn.jsdelivr.net/npm/fuse.js@6.6.2/dist/fuse.min.js";
    script.onload = initSearch;
    document.head.appendChild(script);
  } else {
    initSearch();
  }

  let fuse;
  let searchData = [];

  function initSearch() {
    const base = (window.__DF_BASE_URL || "").replace(/\/$/, "");
    fetch(base + "/search.json")
      .then((r) => r.json())
      .then((data) => {
        searchData = data;
        fuse = new Fuse(data, {
          keys: ["title", "content", "description"],
          threshold: 0.3,
          ignoreLocation: true,
          includeMatches: true,
          includeScore: true,
          minMatchCharLength: 2,
        });
      })
      .catch((error) => console.error("Error loading search data:", error));
  }

  // Build modal. Styling lives in style.css (keeps theming consistent).
  const searchModal = document.createElement("div");
  searchModal.id = "search-modal";
  searchModal.hidden = true;
  searchModal.innerHTML = `
    <div class="search-overlay" id="search-overlay"></div>
    <div class="search-dialog" role="dialog" aria-label="Search documentation">
      <div class="search-dialog-header">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
        <input type="text" id="search-input" placeholder="Search documentation…" autocomplete="off" spellcheck="false">
        <button id="search-close" aria-label="Close search">ESC</button>
      </div>
      <div id="search-results"></div>
    </div>
  `;
  document.body.appendChild(searchModal);

  // Global shortcuts
  document.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
      e.preventDefault();
      showSearch();
      return;
    }
    if (e.key === "Escape" && !searchModal.hidden) {
      hideSearch();
      return;
    }
    // Forward slash opens search when not typing in an input.
    if (
      e.key === "/" &&
      !["INPUT", "TEXTAREA"].includes(
        (document.activeElement && document.activeElement.tagName) || "",
      )
    ) {
      e.preventDefault();
      showSearch();
    }
  });

  document.getElementById("search-overlay").addEventListener("click", hideSearch);
  document.getElementById("search-close").addEventListener("click", hideSearch);

  const searchInput = document.getElementById("search-input");
  let selectedIndex = -1;

  searchInput.addEventListener("input", () => {
    selectedIndex = -1;
    performSearch();
  });

  searchInput.addEventListener("keydown", (e) => {
    const results = document.querySelectorAll(".search-result");
    if (results.length === 0) return;

    if (e.key === "ArrowDown") {
      e.preventDefault();
      selectedIndex = (selectedIndex + 1) % results.length;
      updateSelection(results);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      selectedIndex = selectedIndex <= 0 ? results.length - 1 : selectedIndex - 1;
      updateSelection(results);
    } else if (e.key === "Enter") {
      e.preventDefault();
      const target = selectedIndex >= 0 ? results[selectedIndex] : results[0];
      if (target) target.click();
    }
  });

  // Anything tagged data-search-trigger opens the modal.
  document.querySelectorAll("[data-search-trigger]").forEach((el) => {
    el.addEventListener("click", (e) => {
      e.preventDefault();
      showSearch();
    });
  });

  function updateSelection(results) {
    results.forEach((result, index) => {
      if (index === selectedIndex) {
        result.classList.add("selected");
        result.scrollIntoView({ block: "nearest" });
      } else {
        result.classList.remove("selected");
      }
    });
  }

  function showSearch() {
    searchModal.hidden = false;
    searchInput.focus();
    searchInput.value = "";
    document.getElementById("search-results").innerHTML = "";
    selectedIndex = -1;
  }

  function hideSearch() {
    searchModal.hidden = true;
    selectedIndex = -1;
  }

  function performSearch() {
    const query = searchInput.value.trim();
    const resultsDiv = document.getElementById("search-results");

    if (!query) {
      resultsDiv.innerHTML = "";
      return;
    }

    if (!fuse) {
      resultsDiv.innerHTML = '<div class="search-empty">Loading search index…</div>';
      return;
    }

    const results = fuse.search(query).slice(0, 10);

    if (results.length === 0) {
      resultsDiv.innerHTML = '<div class="search-empty">No results found</div>';
      return;
    }

    resultsDiv.innerHTML = results
      .map((result) => {
        const item = result.item;
        const contentMatch = result.matches.find((m) => m.key === "content");
        const descriptionMatch = result.matches.find((m) => m.key === "description");
        const titleMatch = result.matches.find((m) => m.key === "title");

        let snippet = "";
        if (item.description) {
          snippet += `<div class="search-result-description">${highlightMatches(
            item.description,
            descriptionMatch,
          )}</div>`;
        }
        if (contentMatch && contentMatch.indices && contentMatch.indices.length > 0) {
          snippet += `<div class="search-result-content">${getContentSnippet(
            item.content,
            contentMatch,
          )}</div>`;
        }

        return `
          <div class="search-result" data-url="${escapeHtml(item.url)}">
            <div class="search-result-title">${highlightMatches(item.title, titleMatch)}</div>
            ${snippet}
          </div>
        `;
      })
      .join("");

    resultsDiv.querySelectorAll(".search-result").forEach((el) => {
      el.addEventListener("click", () => {
        window.location.href = el.getAttribute("data-url");
      });
    });
  }

  function getContentSnippet(text, match) {
    if (!match || !match.indices || match.indices.length === 0) return "";

    const best = match.indices.reduce((a, b) =>
      b[1] - b[0] > a[1] - a[0] ? b : a,
    );
    const [start, end] = best;
    const radius = 60;
    const s = Math.max(0, start - radius);
    const e = Math.min(text.length, end + 1 + radius);

    let snippet = "";
    if (s > 0) snippet += "…";
    snippet += escapeHtml(text.slice(s, start));
    snippet += "<mark>" + escapeHtml(text.slice(start, end + 1)) + "</mark>";
    snippet += escapeHtml(text.slice(end + 1, e));
    if (e < text.length) snippet += "…";
    return snippet;
  }

  function escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  function highlightMatches(text, match) {
    if (!match || !match.indices) return escapeHtml(text);

    let result = "";
    let last = 0;
    match.indices.forEach(([start, end]) => {
      result += escapeHtml(text.slice(last, start));
      result += "<mark>" + escapeHtml(text.slice(start, end + 1)) + "</mark>";
      last = end + 1;
    });
    result += escapeHtml(text.slice(last));
    return result;
  }
} // end double-load guard
