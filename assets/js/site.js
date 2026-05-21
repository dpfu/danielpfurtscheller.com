(function() {
  const input = document.querySelector('[data-filter]');
  if (!input) return;

  const output = document.querySelector('output[for="' + input.id + '"]');
  const entries = Array.from(document.querySelectorAll('[data-entry]'));

  input.addEventListener('input', function() {
    const query = input.value.trim().toLowerCase();
    let visible = 0;

    entries.forEach(function(entry) {
      const haystack = (entry.dataset.search || entry.textContent).toLowerCase();
      const match = haystack.includes(query);
      entry.hidden = !match;
      if (match) visible++;
    });

    if (output) {
      output.textContent = query === '' ? '' : (visible === 1 ? '1 Treffer' : visible + ' Treffer');
      output.hidden = query === '';
    }
  });
}());

(function() {
  const tabs = Array.from(document.querySelectorAll('.citation-tab[for]'));
  if (tabs.length === 0) return;

  tabs.forEach(function(tab) {
    tab.addEventListener('click', function() {
      const control = document.getElementById(tab.getAttribute('for'));
      if (!control || control.checked) return;

      control.checked = true;
      control.dispatchEvent(new Event('change', { bubbles: true }));
    });
  });
}());

(function() {
  const buttons = Array.from(document.querySelectorAll('[data-copy-target]'));
  if (buttons.length === 0) return;
  const clipboard = window.navigator && window.navigator.clipboard;
  const canCopyWithClipboard = Boolean(clipboard && window.isSecureContext);
  const canCopyWithCommand = typeof document.execCommand === 'function'
    && typeof document.queryCommandSupported === 'function'
    && document.queryCommandSupported('copy');

  if (!canCopyWithClipboard && !canCopyWithCommand) return;

  function fallbackCopyText(text) {
    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.setAttribute('readonly', '');
    textarea.style.position = 'fixed';
    textarea.style.insetBlockStart = '-1000px';
    textarea.style.insetInlineStart = '-1000px';
    document.body.appendChild(textarea);
    textarea.select();

    try {
      if (!document.execCommand('copy')) {
        throw new Error('Copy command failed');
      }
      return Promise.resolve();
    } catch (error) {
      return Promise.reject(error);
    } finally {
      textarea.remove();
    }
  }

  function copyText(text) {
    if (canCopyWithClipboard) {
      return clipboard.writeText(text).catch(function() {
        return fallbackCopyText(text);
      });
    }

    return fallbackCopyText(text);
  }

  function setButtonState(button, text, className) {
    button.textContent = text;
    button.classList.remove('is-copied', 'is-selected', 'has-copy-error');
    if (className) {
      button.classList.add(className);
    }
  }

  function selectTargetText(target) {
    if (typeof document.createRange !== 'function' || typeof window.getSelection !== 'function') {
      return false;
    }

    const range = document.createRange();
    range.selectNodeContents(target);

    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);

    return true;
  }

  buttons.forEach(function(button) {
    button.hidden = false;

    button.addEventListener('click', function() {
      const target = document.getElementById(button.dataset.copyTarget);
      if (!target) return;

      const originalText = button.textContent;

      copyText(target.textContent.trim()).then(function() {
        setButtonState(button, 'Kopiert', 'is-copied');

        window.setTimeout(function() {
          setButtonState(button, originalText);
        }, 1800);
      }).catch(function() {
        const selected = selectTargetText(target);
        setButtonState(button, selected ? 'Markiert' : 'Nicht kopiert', selected ? 'is-selected' : 'has-copy-error');

        window.setTimeout(function() {
          setButtonState(button, originalText);
        }, 1800);
      });
    });
  });
}());
