
#import <engine::bpm_kernel_bindings>

struct VertexOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec3<f32>,
    @location(2) cull_flag: f32,
}





const AIRPLANE_FACE_COUNT = 10u;

const AIRPLANE_VERTICES = array<vec3<f32>, 7>(
    vec3<f32>(0.0, 0.0, 2.0),     // 0: Nase (+Z = weit weg)
    vec3<f32>(0.0, 0.0, -2.0),    // 1: Heck (-Z = nah dran)
    vec3<f32>(-3.0, 0.0, -0.5),   // 2: L-Flügel
    vec3<f32>(3.0, 0.0, -0.5),    // 3: R-Flügel 
    vec3<f32>(0.0, 0.5, 0.5),     // 4: Kabine Oben
    vec3<f32>(0.0, -0.5, 0.0),    // 5: Rumpf Unten
    vec3<f32>(0.0, 1.0, -2.0),    // 6: Finne
);

const AIRPLANE_FACES = array<vec3<u32>, 10>(
    vec3<u32>(0u, 4u, 2u),  
    vec3<u32>(0u, 3u, 4u),  
    vec3<u32>(2u, 4u, 1u),  
    vec3<u32>(3u, 1u, 4u),  
    vec3<u32>(0u, 2u, 5u),  
    vec3<u32>(0u, 5u, 3u),  
    vec3<u32>(2u, 1u, 5u),  
    vec3<u32>(3u, 5u, 1u),  
    vec3<u32>(1u, 4u, 6u),  // Finne L
    vec3<u32>(1u, 6u, 4u)   // Finne R
);

fn rotate_point(p: vec3<f32>, t: f32) -> vec3<f32> {
    var pos = p;
    let c_y = cos(t * 1.5);
    let s_y = sin(t * 1.5);
    let x_rot = pos.x * c_y + pos.z * s_y;
    let z_rot = -pos.x * s_y + pos.z * c_y;
    pos.x = x_rot;
    pos.z = z_rot;

    let c_x = cos(t * 0.8 + 0.5);
    let s_x = sin(t * 0.8 + 0.5);
    let y_rot = pos.y * c_x - pos.z * s_x;
    let z_rot2 = pos.y * s_x + pos.z * c_x;
    pos.y = y_rot;
    pos.z = z_rot2;
    return pos;
}

@vertex
fn vs_main(@builtin(vertex_index) id: u32) -> VertexOut {
    var out: VertexOut;
    let original_face_index = id / 3u;
    let point_index = id % 3u;
    
    if (original_face_index >= AIRPLANE_FACE_COUNT) {
        out.clip_position = vec4<f32>(0.0, 0.0, 0.0, 0.0);
        return out;
    }
    let t = scene.time;

    // Tiefensortierung (Painters Algorithm)
    // GRUND FÜR DEN FEHLER DAVOR: Ich habe falsch herum sortiert!
    // In unserer Projection Math: z_view = pos.z + 10.0;
    // Ein pos.z von +2.0 bedeutet z_view = 12.0 (weitet weg)
    // Ein pos.z von -2.0 bedeutet z_view = 8.0 (näher dran)
    // -> Größeres pos.z = Weiter weg!
    // Painters Algorithm muss die Dinge die WEIT WEG sind (großes Z), ALS ERSTES zeichnen (Index 0).
    var face_order: array<u32, 10> = array<u32, 10>(0u, 1u, 2u, 3u, 4u, 5u, 6u, 7u, 8u, 9u);
    var face_depth: array<f32, 10>;

    for (var i = 0u; i < 10u; i = i + 1u) {
        let f = AIRPLANE_FACES[i];
        let dp0 = rotate_point(AIRPLANE_VERTICES[f.x], t);
        let dp1 = rotate_point(AIRPLANE_VERTICES[f.y], t);
        let dp2 = rotate_point(AIRPLANE_VERTICES[f.z], t);
        face_depth[i] = dp0.z + dp1.z + dp2.z; 
    }

    // Sortiere absteigend (Große Z-Werte / Weit weg -> Zuerst / Index 0)
    for (var i = 0u; i < 10u; i = i + 1u) {
        for (var j = 0u; j < 9u - i; j = j + 1u) {
            // WENN das linke Element NÄHER ist (kleineres Z) als das rechte Element,
            // tausche sie, damit das weite Element nach links rutscht!
            if (face_depth[face_order[j]] < face_depth[face_order[j + 1u]]) {
                let temp = face_order[j];
                face_order[j] = face_order[j + 1u];
                face_order[j + 1u] = temp;
            }
        }
    }

    let face_index = face_order[original_face_index];
    let face = AIRPLANE_FACES[face_index];

    let w0 = rotate_point(AIRPLANE_VERTICES[face.x], t);
    let w1 = rotate_point(AIRPLANE_VERTICES[face.y], t);
    let w2 = rotate_point(AIRPLANE_VERTICES[face.z], t);

    // CCW Normale
    let edge1 = w1 - w0;
    let edge2 = w2 - w0;
    let normal = normalize(cross(edge1, edge2));
    
    // BACKFACE CULLING 
    // Achtung: Wenn wir auf dem Kopf stehen, dreht sich die Winding Rule um. 
    // Aber wir behalten discard für die Flächen die komplett von uns weg deuten.
    if (normal.z > 0.0) { out.cull_flag = 1.0; } 
    else { out.cull_flag = 0.0; }

    let light_dir = normalize(vec3<f32>(0.5, 1.0, -1.0));
    let intensity = max(abs(dot(normal, light_dir)), 0.3); 
    let base_color = vec3<f32>(1.0, 0.1, 0.1);
    out.color = base_color * intensity + vec3<f32>(0.1, 0.0, 0.0); 

    var pos: vec3<f32>;
    if (point_index == 0u) { pos = w0; }
    else if (point_index == 1u) { pos = w1; }
    else { pos = w2; }

    let bass_scale = 1.0 + max(scene._raw_audio_scalars_do_not_use[u32(0)].x * 0.8, 0.0);
    pos *= bass_scale;

    let distance_from_camera = 10.0;
    let z_view = max(pos.z + distance_from_camera, 0.1);
    let perspective = 4.0 / z_view;
    let aspect_ratio = scene.resolution.x / max(scene.resolution.y, 1.0);

    let screen_x = (pos.x * perspective) / aspect_ratio;
    let screen_y = -(pos.y * perspective); 

    // Wir schreiben pos.z (Tiefenwert) auch in die clip matrix (0.0 bis 1.0 logisch)
    // für korrekte standard rasterization falls es engine-intern doch einfließt
    let clip_z = 1.0 - (perspective * 0.5); 

    out.clip_position = vec4<f32>(screen_x, screen_y, clip_z, 1.0);
    out.uv = pos.xy;
    return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
    if (in.cull_flag > 0.5) { discard; }
    let bg = #color "scene.bg_color";
    return encode_output_alpha(in.color, bg.a);
}

