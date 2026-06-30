import captionsData from './captions.json'

export const UPORTAL_LANG = 'UPORTAL_LANG'

function resolveLanguage() {
  const explicit = globalThis.window?.[UPORTAL_LANG]
  const stored = globalThis.localStorage?.getItem?.('uportal_lang')
  const lang = String(explicit || stored || captionsData.default || 'en').toLowerCase()

  return captionsData[lang] ? lang : captionsData.default
}

function mergeCaptions(base, override) {
  if (!base || typeof base !== 'object') return override
  if (!override || typeof override !== 'object') return base

  const result = Array.isArray(base) ? [...base] : { ...base }

  for (const [key, value] of Object.entries(override)) {
    result[key] = mergeCaptions(base[key], value)
  }

  return result
}

export function getCaptionLanguage() {
  return resolveLanguage()
}

export function getCaptions(section) {
  const lang = resolveLanguage()
  const fallback = captionsData[captionsData.default]?.[section] || {}
  const localized = captionsData[lang]?.[section] || {}

  return mergeCaptions(fallback, localized)
}

export function formatCaption(template, values = {}) {
  return String(template || '').replace(/\{([A-Za-z0-9_]+)\}/g, (match, key) => (
    Object.prototype.hasOwnProperty.call(values, key) ? String(values[key]) : match
  ))
}
