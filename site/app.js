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

        const version = (release.tag_name || "").replace(/^v/, "");
        links.forEach(link => {
            link.href = dmg.browser_download_url;
            // Preserve bespoke button text from the HTML. Only update the
            // two hero/pricing buttons that begin with "Download" or "Start".
            if (/^download/i.test(link.textContent.trim())) {
                link.textContent = version ? `Download Yap ${version}` : "Download Yap";
            }
        });
    } catch (_) {
        // Network failed / offline — links stay on /releases/latest, fine.
    }
})();
