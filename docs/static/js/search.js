// Guard against double-load (e.g. if the site-generator auto-includes scripts
// and the template also adds a <script> tag explicitly).
if (window.__deadfinderSearchLoaded) {
  // already wired up
} else {
  window.__deadfinderSearchLoaded = true;

// Load Fuse.js from CDN if not already loaded
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

// Create search modal
const searchModal = document.createElement("div");
searchModal.id = "search-modal";
searchModal.innerHTML = `
  <div class="search-overlay" id="search-overlay"></div>
  <div class="search-dialog">
    <input type="text" id="search-input" placeholder="Search documentation..." autocomplete="off">
    <div id="search-results"></div>
    <button id="search-close" aria-label="Close search">×</button>
  </div>
`;
searchModal.style.display = "none";
document.body.appendChild(searchModal);

// Styles — prefer the site's CSS variables when present, fall back to neutrals.
const style = document.createElement("style");
style.textContent = `
  #search-modal {
    position: fixed;
    top: 0; left: 0;
    width: 100%; height: 100%;
    z-index: 1000;
  }
  .search-overlay {
    position: absolute;
    top: 0; left: 0;
    width: 100%; height: 100%;
    background: rgba(10, 10, 12, 0.7);
    backdrop-filter: blur(4px);
  }
  .search-dialog {
    position: absolute;
    top: 15%; left: 50%;
    transform: translateX(-50%);
    width: 92%;
    max-width: 640px;
    background: var(--bg-elevated, #1a1a1a);
    color: var(--text, #eaeaea);
    border: 1px solid var(--border-light, #2a2a2a);
    border-radius: 8px;
    box-shadow: 0 10px 40px rgba(0,0,0,0.5);
    padding: 16px;
    max-height: 70vh;
    display: flex;
    flex-direction: column;
  }
  #search-input {
    width: 100%;
    padding: 12px 14px;
    font-size: 15px;
    font-family: inherit;
    background: var(--bg-subtle, #0f0f10);
    color: var(--text, #eaeaea);
    border: 1px solid var(--border, #2a2a2a);
    border-radius: 6px;
    outline: none;
    margin-bottom: 12px;
  }
  #search-input:focus {
    border-color: var(--accent, #6aa9ff);
    box-shadow: 0 0 0 2px rgba(106, 169, 255, 0.2);
  }
  #search-input::placeholder { color: var(--text-muted, #888); }
  #search-results {
    flex: 1;
    overflow-y: auto;
    max-height: calc(70vh - 120px);
  }
  .search-result {
    padding: 10px 12px;
    border-radius: 6px;
    cursor: pointer;
    transition: background 0.15s;
  }
  .search-result + .search-result { margin-top: 4px; }
  .search-result:hover,
  .search-result.selected { background: var(--bg-hover, #232323); }
  .search-result-title {
    font-weight: 600;
    color: var(--accent, #6aa9ff);
    margin-bottom: 2px;
  }
  .search-result-description,
  .search-result-content {
    font-size: 13px;
    color: var(--text-muted, #9a9a9a);
    line-height: 1.45;
  }
  .search-result-content { margin-top: 4px; opacity: 0.9; }
  .search-result-content mark,
  .search-result-title mark,
  .search-result-description mark {
    background: rgba(106, 169, 255, 0.25);
    color: inherit;
    padding: 0 2px;
    border-radius: 2px;
  }
  #search-close {
    position: absolute;
    top: 8px; right: 8px;
    background: transparent;
    border: none;
    color: var(--text-muted, #9a9a9a);
    width: 28px; height: 28px;
    font-size: 22px;
    cursor: pointer;
    line-height: 1;
  }
  #search-close:hover { color: var(--text, #eaeaea); }

  /* Topbar search trigger (button-styled) */
  .topbar-search[data-search-trigger] {
    cursor: pointer;
  }
  .topbar-search[data-search-trigger] kbd {
    font-family: inherit;
    font-size: 11px;
    padding: 2px 6px;
    border: 1px solid var(--border-light, #2a2a2a);
    border-radius: 4px;
    color: var(--text-muted, #9a9a9a);
    margin-left: 8px;
  }
`;
document.head.appendChild(style);

// Global shortcuts
document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "k") {
    e.preventDefault();
    showSearch();
  }
  if (e.key === "Escape" && searchModal.style.display !== "none") {
    hideSearch();
  }
  // Forward slash also opens search when not focused on an input
  if (
    e.key === "/" &&
    !["INPUT", "TEXTAREA"].includes(document.activeElement && document.activeElement.tagName)
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
    if (selectedIndex >= 0 && selectedIndex < results.length) {
      results[selectedIndex].click();
    } else if (results.length > 0) {
      results[0].click();
    }
  }
});

// Wire any page element opted in via data-search-trigger
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
  searchModal.style.display = "block";
  searchInput.focus();
  searchInput.value = "";
  document.getElementById("search-results").innerHTML = "";
  selectedIndex = -1;
}

function hideSearch() {
  searchModal.style.display = "none";
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
    resultsDiv.innerHTML = '<div class="search-result">Loading search index...</div>';
    return;
  }

  const results = fuse.search(query).slice(0, 10);

  if (results.length === 0) {
    resultsDiv.innerHTML = '<div class="search-result">No results found</div>';
    return;
  }

  resultsDiv.innerHTML = results
    .map((result) => {
      const item = result.item;
      const contentMatch = result.matches.find((m) => m.key === "content");
      const descriptionMatch = result.matches.find((m) => m.key === "description");

      let snippet = "";
      if (item.description) {
        snippet = `<div class="search-result-description">${highlightMatches(
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
        <div class="search-result" onclick="window.location.href='${item.url}'">
          <div class="search-result-title">${highlightMatches(
            item.title,
            result.matches.find((m) => m.key === "title"),
          )}</div>
          ${snippet}
        </div>
      `;
    })
    .join("");
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
  if (s > 0) snippet += "...";
  snippet += escapeHtml(text.slice(s, start));
  snippet += "<mark>" + escapeHtml(text.slice(start, end + 1)) + "</mark>";
  snippet += escapeHtml(text.slice(end + 1, e));
  if (e < text.length) snippet += "...";
  return snippet;
}

function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

function highlightMatches(text, match) {
  if (!match || !match.indices) return text;

  let result = "";
  let last = 0;
  match.indices.forEach(([start, end]) => {
    result += text.slice(last, start);
    result += "<mark>" + text.slice(start, end + 1) + "</mark>";
    last = end + 1;
  });
  result += text.slice(last);
  return result;
}

} // end double-load guard
