
import bpy
import json
import sys

def get_fcurves_and_drivers(obj):
    anim_data = obj.animation_data
    if not anim_data:
        return None
    res = {}
    if anim_data.action:
        res['fcurves'] = []
        for fc in anim_data.action.fcurves:
            res['fcurves'].append({
                'data_path': fc.data_path,
                'array_index': fc.array_index,
                'keyframe_count': len(fc.keyframe_points)
            })
    if anim_data.drivers:
        res['drivers'] = []
        for d in anim_data.drivers:
            res['drivers'].append({
                'data_path': d.data_path,
                'array_index': d.array_index,
                'expression': d.driver.expression if d.driver.type == 'SCRIPTED' else d.driver.type
            })
    return res

def extract_rna_props(item, skip=None):
    if skip is None: skip = set()
    skip.update(['rna_type', 'name', 'type', 'inputs', 'outputs'])
    props = {}
    if hasattr(item, 'bl_rna'):
        for k in item.bl_rna.properties.keys():
            if k in skip: continue
            try:
                v = getattr(item, k)
                if isinstance(v, (int, float, str, bool)):
                    props[k] = round(v, 4) if isinstance(v, float) else v
                elif type(v).__name__ in ['Color', 'Vector', 'Euler', 'Quaternion']:
                    props[k] = [round(x, 4) for x in v]
                elif type(v).__name__ == 'bpy_prop_array':
                    props[k] = [round(x, 4) if isinstance(x, float) else x for x in v]
                elif hasattr(v, 'name'):
                    props[k] = v.name
            except:
                pass
    return props

def get_modifiers(obj):
    res = []
    for mod in obj.modifiers:
        mod_info = {
            'name': mod.name,
            'type': mod.type,
            'show_viewport': mod.show_viewport
        }
        mod_info.update(extract_rna_props(mod, skip={'name', 'type', 'show_viewport', 'show_render', 'show_in_editmode', 'show_on_cage', 'is_active'}))
        res.append(mod_info)
    return res

def get_custom_properties(obj):
    res = {}
    for K in obj.keys():
        if K not in '_RNA_UI':
            val = obj[K]
            if type(val).__name__ == 'IDPropertyArray':
                res[K] = list(val)
            else:
                res[K] = val
    return res

def extract_node_inputs(node):
    inputs = {}
    for inp in node.inputs:
        val = None
        if hasattr(inp, 'default_value'):
            dv = inp.default_value
            if hasattr(dv, '__len__') and not isinstance(dv, str):
                val = [round(float(v), 6) for v in dv]
            elif isinstance(dv, (int, float)):
                val = round(float(dv), 6)
            elif isinstance(dv, bool):
                val = dv
            else:
                val = str(dv)
        inputs[inp.name] = val
    return inputs

def extract_node_detail(node):
    nd = {
        'name': node.name,
        'type': node.type,
        'label': node.label or None,
        'inputs': extract_node_inputs(node),
    }
    nd.update(extract_rna_props(node, skip={'name', 'type', 'label', 'location', 'width', 'height', 'width_hidden', 'height_hidden', 'color', 'hide', 'select', 'parent', 'dimensions'}))
    
    # Type-specific properties
    if node.type == 'VALTORGB':  # ColorRamp
        ramp = node.color_ramp
        nd['interpolation'] = ramp.interpolation
        nd['elements'] = [
            {'position': round(e.position, 6), 'color': [round(c, 6) for c in e.color]}
            for e in ramp.elements
        ]
    elif node.type == 'GROUP':
        nd['node_tree_name'] = node.node_tree.name if node.node_tree else None
    return nd

def extract_links(node_tree):
    return [
        {
            'from_node': lk.from_node.name,
            'from_socket': lk.from_socket.name,
            'to_node': lk.to_node.name,
            'to_socket': lk.to_socket.name,
        }
        for lk in node_tree.links
    ]

def extract_material_animation(mat):
    anim = {}
    if not mat.node_tree or not mat.node_tree.animation_data:
        return anim
    ad = mat.node_tree.animation_data
    if ad.drivers:
        anim['drivers'] = []
        for d in ad.drivers:
            drv = {
                'data_path': d.data_path,
                'array_index': d.array_index,
            }
            if d.driver:
                drv['expression'] = d.driver.expression if d.driver.type == 'SCRIPTED' else d.driver.type
                drv['variables'] = []
                for v in d.driver.variables:
                    vi = {'name': v.name, 'type': v.type}
                    for t in v.targets:
                        vi['target_id'] = t.id.name if t.id else None
                        vi['target_data_path'] = t.data_path
                    drv['variables'].append(vi)
            anim['drivers'].append(drv)
    if ad.action:
        anim['fcurves'] = []
        for fc in ad.action.fcurves:
            kfs = [{'frame': round(k.co[0], 2), 'value': round(k.co[1], 4)} for k in fc.keyframe_points[:12]]
            anim['fcurves'].append({
                'data_path': fc.data_path,
                'array_index': fc.array_index,
                'keyframe_count': len(fc.keyframe_points),
                'keyframes': kfs,
            })
    return anim

def extract_materials():
    materials = []
    for mat in bpy.data.materials:
        mat_info = {
            'name': mat.name,
            'use_nodes': mat.use_nodes
        }
        if mat.use_nodes and mat.node_tree:
            mat_info['nodes'] = [extract_node_detail(n) for n in mat.node_tree.nodes]
            mat_info['links'] = extract_links(mat.node_tree)
            mat_anim = extract_material_animation(mat)
            if mat_anim:
                mat_info['animation'] = mat_anim
        materials.append(mat_info)
    return materials

try:
    data = {
        'scene': {
            'fps': bpy.context.scene.render.fps,
            'frame_start': bpy.context.scene.frame_start,
            'frame_end': bpy.context.scene.frame_end,
        },
        'materials': extract_materials(),
        'objects': []
    }

    for obj in bpy.context.scene.objects:
        if obj.type not in ['MESH', 'CAMERA', 'LIGHT', 'EMPTY']:
            continue
        
        obj_data = {
            'name': obj.name,
            'type': obj.type,
            'location': [round(x, 4) for x in obj.location],
            'rotation_euler': [round(x, 4) for x in obj.rotation_euler],
            'scale': [round(x, 4) for x in obj.scale],
        }
        
        custom_props = get_custom_properties(obj)
        if custom_props:
            obj_data['custom_properties'] = custom_props
            
        modifiers = get_modifiers(obj)
        if modifiers:
            obj_data['modifiers'] = modifiers
            
        if obj.type == 'MESH':
            obj_data['material_slots'] = [mat.name for mat in obj.data.materials if mat]
            obj_data['vertices'] = len(obj.data.vertices)
            
        if obj.type == 'CAMERA':
            obj_data['camera'] = {
                'lens': round(obj.data.lens, 4),
                'sensor_width': round(obj.data.sensor_width, 4),
                'clip_start': round(obj.data.clip_start, 4),
                'clip_end': round(obj.data.clip_end, 4),
                'type': obj.data.type
            }
            
        anim = get_fcurves_and_drivers(obj)
        if anim:
            obj_data['animation'] = anim
            
        data['objects'].append(obj_data)
        
    def sanitize(v):
        if isinstance(v, dict):
            return {str(k): sanitize(val) for k, val in v.items()}
        elif isinstance(v, list):
            return [sanitize(val) for val in v]
        elif isinstance(v, (int, float, str, bool, type(None))):
            return v
        else:
            return str(v)
            
    print("---BPM_JSON_START---")
    print(json.dumps(sanitize(data), indent=2))
    print("---BPM_JSON_END---")
except Exception as e:
    import traceback
    traceback.print_exc(file=sys.stdout)



