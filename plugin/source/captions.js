globalThis.UPortalCaptions = (() => {
  let captionsPromise = null

  function normalizeLanguage(value) {
    return String(value || '')
      .trim()
      .toLowerCase()
      .replace('_', '-')
      .split('-')[0]
  }

  function runtimeUrl(path) {
    if (globalThis.browser?.runtime?.getURL) return browser.runtime.getURL(path)
    return path
  }

  async function loadAll() {
    if (!captionsPromise) {
      captionsPromise = fetch(runtimeUrl('captions.json')).then(response => response.json())
    }
    return captionsPromise
  }

  function getPreferredLanguage(data) {
    const preferredLanguage = normalizeLanguage(data.preferred)
    if (data[preferredLanguage]) return preferredLanguage

    const thunderbirdLanguage = globalThis.browser?.i18n?.getUILanguage?.()
    const browserLanguage = globalThis.navigator?.language
    const language = normalizeLanguage(thunderbirdLanguage || browserLanguage)
    return data[language] ? language : data.default || 'en'
  }

  function mergeCaptions(base, override) {
    return { ...(base || {}), ...(override || {}) }
  }

  async function get(section) {
    const data = await loadAll()
    const defaultLanguage = data.default || 'en'
    const language = getPreferredLanguage(data)
    return mergeCaptions(data[defaultLanguage]?.[section], data[language]?.[section])
  }

  function format(template, values = {}) {
    return String(template || '').replace(/\{([A-Za-z0-9_]+)\}/g, (match, key) => (
      Object.prototype.hasOwnProperty.call(values, key) ? String(values[key]) : match
    ))
  }

  return { get, format, getPreferredLanguage }
})()
