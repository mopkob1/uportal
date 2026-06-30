const params = new URLSearchParams(location.search)
const id = params.get('id') || ''
const error = params.get('error') || ''
let captions = null

document.getElementById('sendPlain').addEventListener('click', () => choose('send_plain'))
document.getElementById('saveDraft').addEventListener('click', () => choose('cancel'))

async function choose(choice) {
  try {
    await browser.runtime.sendMessage({
      type: 'server-failure-decision',
      id,
      choice
    })
  } finally {
    window.close()
  }
}

async function init() {
  captions = await UPortalCaptions.get('confirm')
  document.title = captions.title
  document.getElementById('heading').textContent = captions.heading
  document.getElementById('bodyText').textContent = captions.body
  document.getElementById('sendPlain').textContent = captions.sendPlain
  document.getElementById('saveDraft').textContent = captions.saveDraft
  document.getElementById('hintText').textContent = captions.hint
  document.getElementById('error').textContent = error || captions.defaultError
}

init().catch(() => {
  document.getElementById('error').textContent = error || 'Server unavailable'
})
