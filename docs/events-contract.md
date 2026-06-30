# Events Contract

Events are written under:

```text
/data/files/uportal/events/
```

Expected indexes:

```text
raw/*.json
by-pub/*.json
by-event/*.json
by-link/*.json
by-uid/*.json
```

## Event Model

| Type | Moment | Event |
| --- | --- | --- |
| `redirect` | short landing opened | `open` |
| `redirect` | user leaves to target URL | `click` |
| `page` | short page opened | `open` |
| `page` | page shell loaded | `page_view` |
| `page` | page content fetched | `content` |
| `download` | short landing opened | `open` |
| `download` | file request started | `download` |
| `pixel` | pixel image requested | `pixel` |

## Click Decrement

`remaining_clicks` is decremented only for real actions:

| Type | Decrement Event |
| --- | --- |
| `redirect` | `click` |
| `download` | `download` |
| `page` | `content` |
| `pixel` | never |

Freshness is checked by `portal.js`; shhoook does not own freshness logic.
