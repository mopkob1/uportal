export function extractItems(payload) {
  if (Array.isArray(payload)) return payload

  if (Array.isArray(payload?.items)) return payload.items
  if (Array.isArray(payload?.links)) return payload.links
  if (Array.isArray(payload?.events)) return payload.events
  if (Array.isArray(payload?.data)) return payload.data

  if (Array.isArray(payload?.message)) {
    if (Array.isArray(payload.message[0]?.items)) return payload.message[0].items
    if (Array.isArray(payload.message[0]?.links)) return payload.message[0].links
    if (Array.isArray(payload.message[0]?.data)) return payload.message[0].data

    return payload.message.filter((item) => item && typeof item === 'object')
  }

  return []
}

export function extractPaged(payload, fallback = {}) {
  const defaults = {
    items: [],
    page: 1,
    limit: 50,
    total: 0,
    has_next: false,
    ...fallback
  }

  if (Array.isArray(payload?.message) && payload.message[0]?.items) {
    return {
      ...defaults,
      ...payload.message[0],
      items: payload.message[0].items || []
    }
  }

  if (Array.isArray(payload?.items)) {
    return {
      ...defaults,
      ...payload,
      items: payload.items || []
    }
  }

  return defaults
}

export function normalizeLink(raw) {
  const shortValue = raw.short || raw.short_url || raw.url || raw.href || ''
  return {
    id: `${raw.publication_id || raw.publication || ''}:${raw.token || ''}`,
    publication_id: raw.publication_id || raw.publication || '',
    token: raw.token || '',
    type: raw.type || '',
    status: raw.status || 'published',
    short: shortValue,
    title: raw.title || raw.subj || '',
    description: raw.description || '',
    link: raw.link || '',
    remaining_clicks: raw.remaining_clicks ?? '',
    fresh_until: raw.fresh_until ?? '',
    raw
  }
}

export function groupLinksToPublications(links) {
  const map = new Map()

  for (const link of links) {
    const id = link.publication_id || 'unknown'
    if (!map.has(id)) {
      map.set(id, {
        publication_id: id,
        links: [],
        links_count: 0,
        types: new Set()
      })
    }

    const publication = map.get(id)
    publication.links.push(link)
    publication.links_count += 1
    if (link.type) publication.types.add(link.type)
  }

  return Array.from(map.values()).map((item) => ({
    ...item,
    types: Array.from(item.types)
  }))
}
