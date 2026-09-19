# Walking podcast: the flow we want to build

The voice call stays open throughout the walk. Location and photos travel to
the backend alongside that call, and their results are fed back into the same
conversation.

## The whole system

```mermaid
flowchart LR
    USER["Walker"] --> APP["Mobile app"]
    APP -->|"Voice"| LIVE["Gemini Live podcast"]
    APP -->|"Location"| ROUTE["Route service"]
    APP -->|"Photo"| PHOTO["Photo checker"]
    ROUTE -->|"Updated route"| LIVE
    PHOTO -->|"Photo result"| LIVE
    LIVE -->|"Spoken response"| APP
```

There are three parallel data paths:

- Voice stays connected to Gemini Live.
- The app watches location and the backend updates the route.
- A separate vision request checks a still photo and returns the result to the
  live conversation.

## Normal walking and a wrong turn

```mermaid
flowchart TD
    A["App receives a GPS update"] --> B["Measure distance from the route"]
    B --> C{"Off route for several accurate updates?"}
    C -->|"No"| D["Keep the current route"]
    D --> E["Keep talking about the current place"]
    C -->|"Yes"| F["Send a route deviation event"]
    F --> G["Server compares returning with continuing"]
    G --> H["Server commits the best route"]
    H --> I["App redraws the route"]
    H --> J["Gemini explains the change aloud"]
```

The app performs the quick detection. A useful starting rule is **30–50 metres
away from the route for three accurate GPS updates**. The server makes the
final rerouting decision.

This automatic path does not need a model tool call. A model tool is still
useful when the walker explicitly asks, “Can we go through Berwick Street?”

## Narration stays tied to location

```mermaid
flowchart LR
    A["Arrive at Chinatown Gate"] --> B["Tell one short story beat"]
    B --> C{"Has location reached the next stop?"}
    C -->|"No"| D["Tell a fresh angle about Chinatown Gate"]
    D --> C
    C -->|"Yes"| E["Move the narration anchor to Gerrard Street"]
    E --> F["Begin stories about Gerrard Street"]
```

Finishing a narration turn never moves the story to another place. Only a
location update or a committed reroute changes the narration anchor.

## Asking for and checking a photo

```mermaid
flowchart TD
    A["Gemini calls request_photo"] --> B["App shows the camera request"]
    B --> C["Walker takes a photo"]
    C --> D["App uploads the photo with GPS and place ID"]
    D --> E["Gemini Flash checks the image"]
    E --> F{"Does it match the expected place?"}
    F -->|"Yes"| G["Save the place memory"]
    G --> H["Gemini confirms it and continues the story"]
    F -->|"No"| I["Explain what is missing"]
    I --> J["Ask for one clearer photo"]
    J --> C
    F -->|"Uncertain"| K["Ask for a wider or sharper photo"]
    K --> C
```

The `request_photo` tool returns immediately; it does not wait while the walker
uses the camera. The server stores a pending photo request and reconnects the
result using its request ID.

The photo upload is outside the PCM audio stream, but it remains part of the
same walk and conversation:

```text
Live call asks for photo
  → app opens camera
  → backend checks photo
  → result enters the live call
  → Gemini answers aloud
```

## Who owns each decision

| Decision | Owner | How it reaches the conversation |
| --- | --- | --- |
| User started speaking | Gemini Live | Voice activity detection |
| Current location | App | Location event |
| Possibly off route | App | Local distance check and debounce |
| New route | Backend | Route update event |
| Continue narration at the current place | Backend session state | Narration prompt |
| Ask for a photo | Model | `request_photo` tool |
| Capture and upload photo | App | Camera plus upload endpoint |
| Decide whether the photo matches | Gemini Flash vision | Structured photo result |
| Confirm or request another photo | Gemini Live | Spoken response |

