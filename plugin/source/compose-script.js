browser.runtime.onMessage.addListener((message) => {
  if (message?.type !== 'uportal:insert-html') return
  insertHtmlAtCursor(message.html || '')
})

function insertHtmlAtCursor(html) {
  const active = document.activeElement

  if (active && (active.tagName === 'TEXTAREA' || active.tagName === 'INPUT')) {
    const text = htmlToPlainText(html)
    const start = active.selectionStart || 0
    const end = active.selectionEnd || 0
    active.value = `${active.value.slice(0, start)}${text}${active.value.slice(end)}`
    active.selectionStart = active.selectionEnd = start + text.length
    active.dispatchEvent(new Event('input', { bubbles: true }))
    return
  }

  if (document.queryCommandSupported && document.queryCommandSupported('insertHTML')) {
    document.execCommand('insertHTML', false, html)
    return
  }

  if (document.queryCommandSupported && document.queryCommandSupported('insertText')) {
    document.execCommand('insertText', false, htmlToPlainText(html))
  }
}

function htmlToPlainText(html) {
  const div = document.createElement('div')
  div.innerHTML = html
  return div.textContent || div.innerText || ''
}
