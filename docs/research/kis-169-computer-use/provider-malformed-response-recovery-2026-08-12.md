# Provider malformed-response recovery

Date: 2026-08-12
Session: `CU-F13CE2A142DB`

## Observed failure

- **Verified**: the voice instruction was `Open helium and play some focus music on YouTube and
  uh change the brightness to full and sound to 50%`.
- **Verified**: Suniye completed 39 native tool calls before the failure.
- **Verified**: step 39 was an app-scoped `press_key` call. It completed successfully.
- **Verified**: the next model request failed before another tool call was decoded, with
  `LLM provider returned malformed response`.
- **Verified**: Suniye's provider retry policy retried transport failures and HTTP 5xx responses,
  but explicitly did not retry `malformedResponse` or `emptyOutput`.
- **Verified**: the conversation store retained tool calls and tool outputs, but not the raw HTTP
  response body. The precise provider response shape from this failed turn cannot be recovered.

## Reference comparison

- **Verified**: the inspected Codex binary has separate request and sampling-stream retry paths.
  It includes `request_max_retries`, `stream_max_retries`, and
  `stream disconnected - retrying sampling request (`.
- **Verified**: these provider retries are separate from the native Computer Use transport.
- **Verified**: replaying a model sampling request does not replay an already completed native
  action.
- **Unknown**: the DMG does not expose the exact classification or retry count used for an HTTP
  success response whose body has no usable assistant output.

## Correction

- **Implemented**: Computer Use now treats malformed and empty model output as retryable sampling
  failures under its existing bounded retry budget and exponential backoff.
- **Implemented**: only the model request is replayed. The preceding native action is not replayed.
- **Verified by regression test**: a first HTTP 200 response with no usable choice followed by a
  valid response now recovers after one retry. The test failed with the original policy and passes
  with the correction.

## Remaining unknown

- **Unknown**: whether this specific live response was empty, truncated, or used an unsupported
  provider response shape. A future occurrence can only distinguish those cases if sanitized
  response-shape diagnostics are added before decoding; logging raw provider content is not
  required for this recovery and was not added.
