// ---------------------------------------------------------------------------
// Color helpers — common color encoding operations for generic WGSL shaders.
// Usage: #import <bpm/color_utils.wgsl>
//
// IMPLICIT CONTRACT: The consuming shader MUST define a SceneUniform struct
// with a field `_raw_params_do_not_use: array<vec4<f32>, N>` and bind it as
// `var<uniform> scene: SceneUniform` at @group(0) @binding(0).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// BpmColor — type-safe color wrapper enforcing pre-multiplied RGB.
//
// Content shaders MUST NOT construct this type directly.  Use the safe
// getter functions below (e.g. get_scene_color) instead.  The shader-audit
// AST enforcer will reject any direct BpmColor(...) construction outside
// of the whitelisted utility functions.
//
// IMPORTANT: Do NOT call get_scene_color() with manual index numbers!
// Use the #color "scene.target_name" macro in your shader source.
// The engine will replace it with the correct get_scene_color(INDEX) call
// at compile time.
// ---------------------------------------------------------------------------

struct BpmColor {
  rgb: vec3<f32>, // Pre-multiplied with alpha (RGB * A)
  a: f32, // Raw alpha channel for background transport
}

// ---------------------------------------------------------------------------
// Safe getters — the ONLY sanctioned way to obtain a BpmColor.
// ---------------------------------------------------------------------------

/// Returns the scene color at the given param slot index.
/// RGB is pre-multiplied by the slot's alpha channel to guarantee correct
/// compositing downstream.
/// The raw alpha is preserved for background-transport in encode_output_alpha.
fn get_scene_color(index: i32) -> BpmColor {
  let raw = scene._raw_params_do_not_use[index];
  return BpmColor(raw.rgb * raw.a, raw.a);
}

/// Convenience constant for a fully opaque background.
fn bg_opaque() -> f32 {
  return 1.0;
}

// ---------------------------------------------------------------------------
// Output encoding
// ---------------------------------------------------------------------------

/// Encodes the final output color with additive luma transparency.
///
/// Takes a pre-multiplied RGB color (vec3) and the background alpha layer
/// configuration.  Calculates a transparency mask so that bright glowing
/// elements become opaque, while the background drops away smoothly if the
/// user configured it to be transparent.
///
/// Usage:
///   let bg = #color "scene.bg_color";
///   // ... mix colors freely using .rgb ...
///   return encode_output_alpha(final_mixed_rgb, bg.a);
fn encode_output_alpha(color: vec3<f32>, base_bg_alpha: f32) -> vec4<f32> {
  let final_color = max(color, vec3<f32>(0.0));
  let luma = dot(final_color, vec3<f32>(0.299, 0.587, 0.114));

  // Additive Luma-Helligkeit generiert die erforderliche opacity-Matte
  // für Pixel, falls der native Hintergrund transparent gesetzt ist.
  let out_alpha = clamp(max(base_bg_alpha, luma * 1.5), 0.0, 1.0);
  return vec4<f32>(final_color, out_alpha);
}
