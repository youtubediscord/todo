(function () {
  const DISQUS_SHORTNAME = 'loop-uh';
  const BASE_URL = 'https://publish.obsidian.md/zapret';

  console.log('publish.js loaded from Notes/Privacy root');

  function cleanPath() {
    const p = window.location.pathname.replace(/\/$/, '');
    return p || '/zapret';
  }

  function pageUrl() {
    return BASE_URL + cleanPath();
  }

  function pageId() {
    return cleanPath();
  }

  function insertContainer() {
    if (document.getElementById('disqus_thread')) return;

    const host =
      document.querySelector('.markdown-preview-view') ||
      document.querySelector('.markdown-reading-view') ||
      document.querySelector('main') ||
      document.body;

    if (!host) return;

    const title = document.createElement('h3');
    title.textContent = 'Комментарии';
    title.style.marginTop = '2rem';
    host.appendChild(title);

    const thread = document.createElement('div');
    thread.id = 'disqus_thread';
    host.appendChild(thread);
  }

  function setDisqusConfig() {
    window.disqus_config = function () {
      this.page.url = pageUrl();
      this.page.identifier = pageId();
      this.page.title = document.title;
    };
  }

  function loadOrReset() {
    setDisqusConfig();

    if (!document.getElementById('disqus-embed-script')) {
      const s = document.createElement('script');
      s.id = 'disqus-embed-script';
      s.src = `https://${DISQUS_SHORTNAME}.disqus.com/embed.js`;
      s.type = 'text/javascript';
      s.async = true;
      s.setAttribute('data-timestamp', String(Date.now()));
      (document.head || document.body).appendChild(s);
      return;
    }

    if (window.DISQUS && typeof window.DISQUS.reset === 'function') {
      window.DISQUS.reset({
        reload: true,
        config: function () {
          this.page.url = pageUrl();
          this.page.identifier = pageId();
          this.page.title = document.title;
        }
      });
    }
  }

  function init() {
    insertContainer();
    loadOrReset();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
