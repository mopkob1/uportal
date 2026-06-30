import { getCaptions } from '../captions'

const DB_NAME = 'uportal-draft-assets'
const DB_VERSION = 1
const STORE_NAME = 'assets'

const commonCaptions = getCaptions('common')

let dbPromise = null

export async function putDraftAsset(key, dataUrl) {
  if (!key || !dataUrl) return ''

  const db = await openDb()

  await runRequest(
      db
          .transaction(STORE_NAME, 'readwrite')
          .objectStore(STORE_NAME)
          .put({ key, dataUrl, updated_at: new Date().toISOString() })
  )

  return key
}

export async function getDraftAsset(key) {
  if (!key) return ''

  const db = await openDb()
  const item = await runRequest(
      db
          .transaction(STORE_NAME, 'readonly')
          .objectStore(STORE_NAME)
          .get(key)
  )

  return item?.dataUrl || ''
}

export async function deleteDraftAsset(key) {
  if (!key) return

  const db = await openDb()

  await runRequest(
      db
          .transaction(STORE_NAME, 'readwrite')
          .objectStore(STORE_NAME)
          .delete(key)
  )
}

export async function deleteDraftAssets(keys = []) {
  const uniqueKeys = Array.from(new Set(keys.filter(Boolean)))
  if (!uniqueKeys.length) return

  const db = await openDb()
  const transaction = db.transaction(STORE_NAME, 'readwrite')
  const store = transaction.objectStore(STORE_NAME)

  uniqueKeys.forEach(key => store.delete(key))

  await runTransaction(transaction)
}

export async function deleteDraftAssetsByPrefix(prefix) {
  if (!prefix) return

  const db = await openDb()
  const transaction = db.transaction(STORE_NAME, 'readwrite')
  const store = transaction.objectStore(STORE_NAME)
  const request = store.openCursor()

  request.onsuccess = () => {
    const cursor = request.result
    if (!cursor) return

    if (String(cursor.key || '').startsWith(prefix)) {
      cursor.delete()
    }

    cursor.continue()
  }

  request.onerror = () => {
    transaction.abort()
  }

  await runTransaction(transaction)
}

export async function deleteDraftAssetsForDraft(draft) {
  if (!draft) return

  const keys = [
    draft.imageDataKey,
    draft.fileDataKey,
    ...(Array.isArray(draft.form?.files)
        ? draft.form.files.map(file => file?.fileDataKey)
        : [])
  ]

  await deleteDraftAssets(keys)

  if (draft.draft_id) {
    await deleteDraftAssetsByPrefix(`${draft.draft_id}:`)
  }
}

function openDb() {
  if (dbPromise) return dbPromise

  dbPromise = new Promise((resolve, reject) => {
    if (!window.indexedDB) {
      reject(new Error(commonCaptions.indexedDbUnavailable))
      return
    }

    const request = window.indexedDB.open(DB_NAME, DB_VERSION)

    request.onupgradeneeded = () => {
      const db = request.result

      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: 'key' })
      }
    }

    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })

  return dbPromise
}

function runRequest(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

function runTransaction(transaction) {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve()
    transaction.onerror = () => reject(transaction.error)
    transaction.onabort = () => reject(transaction.error || new Error('IndexedDB transaction aborted'))
  })
}
