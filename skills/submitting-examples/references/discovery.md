# One-time form discovery & setup

Runs only when `${CLAUDE_PLUGIN_DATA}/config.json` is missing or incomplete.
Produces that file, then Step 0 continues.

1. Determine the form URL. If the user configured `form_url` (plugin user config)
   and it is available, use it. Otherwise ask: "What's the URL of the Google Form
   to submit examples to?"
2. Fetch the form's HTML:
   `curl -sL "<viewform-url>"` (a `/viewform` URL is expected).
3. In the HTML, find the `FB_PUBLIC_LOAD_DATA_` array. For each question extract
   its visible text and its `entry.<id>` (the numeric id in the question's field
   descriptor). Also note whether the form collects email (a `type="email"`
   input is present).
4. Map questions to fields by keyword on the question text:
   `repository` → `repo`, `language`/`stack` → `stack`, `context` → `context`,
   `good` → `good`, `bad` → `bad`.
5. If any field is unmatched or ambiguous, show the user the discovered questions
   and ask which maps to which. Do not guess silently.
6. Normalize the form URL to its `/formResponse` endpoint and write
   `${CLAUDE_PLUGIN_DATA}/config.json`:
   ```json
   {
     "form_url": "https://docs.google.com/forms/d/e/<id>/formResponse",
     "collects_email": true,
     "fields": {
       "repo": "entry.<id>",
       "stack": "entry.<id>",
       "context": "entry.<id>",
       "good": "entry.<id>",
       "bad": "entry.<id>"
     }
   }
   ```
