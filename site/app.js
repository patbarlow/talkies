// Frosted glass header on scroll.
(function () {
    const header = document.querySelector("header");
    if (!header) return;
    const update = () => header.classList.toggle("scrolled", window.scrollY > 10);
    update();
    window.addEventListener("scroll", update, { passive: true });
})();

// Point every download link at the DMG asset from the latest GitHub release.
// Falls back to the /releases/latest page if the API is down or rate-limited.
(async function () {
    const links = document.querySelectorAll(".download-link");
    try {
        const res = await fetch("https://api.github.com/repos/patbarlow/talkies/releases/latest", {
            headers: { "Accept": "application/vnd.github+json" }
        });
        if (!res.ok) return;
        const release = await res.json();
        const dmg = (release.assets || []).find(a => a.name.endsWith(".dmg"));
        if (!dmg) return;

        links.forEach(link => {
            link.href = dmg.browser_download_url;
        });
    } catch (_) {
        // Network failed / offline — links stay on /releases/latest, fine.
    }
})();
