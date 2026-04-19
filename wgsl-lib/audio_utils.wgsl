// ---------------------------------------------------------------------------
// Audio helpers — common audio decoding operations for generic WGSL shaders.
// Usage: #import <bpm/audio_utils.wgsl>
//
// IMPLICIT CONTRACT: The consuming shader MUST define a SceneUniform struct
// with a field `_raw_audio_scalars_do_not_use: array<vec4<f32>, N>` and bind it as
// `var<uniform> scene: SceneUniform` at @group(0) @binding(0).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// BpmAudioSignal — type-safe audio wrapper enforcing safe clamp scaling.
//
// Content shaders MUST NOT construct this type directly. Use the safe
// getter function below (get_audio_scalar) instead. The shader-audit
// AST enforcer will reject any direct BpmAudioSignal(...) construction outside
// of the whitelisted utility functions.
//
// IMPORTANT: Do NOT call get_audio_scalar() with manual index numbers!
// Use the #audio "audio.target_name" macro in your shader source.
// The engine will replace it with the correct get_audio_scalar(INDEX) call
// at compile time.
// ---------------------------------------------------------------------------

struct BpmAudioSignal {
  value: f32,
  clamped_safe: f32, // Guarantees the value is tightly bounded between 0.0 and 1.0
}

// ---------------------------------------------------------------------------
// Safe getters — the ONLY sanctioned way to obtain a BpmAudioSignal.
// ---------------------------------------------------------------------------

/// Returns the audio signal at the given scalar index.
fn get_audio_scalar(index: i32) -> BpmAudioSignal {
  let vec_idx = u32(index) / 4u;
  let comp_idx = u32(index) % 4u;
  let slot = scene._raw_audio_scalars_do_not_use[vec_idx];

  var raw_val = 0.0;
  if comp_idx == 0u {
    raw_val = slot.x;
  } else if comp_idx == 1u {
    raw_val = slot.y;
  } else if comp_idx == 2u {
    raw_val = slot.z;
  } else {
    raw_val = slot.w;
  }

  return BpmAudioSignal(raw_val, clamp(raw_val, 0.0, 1.0));
}
