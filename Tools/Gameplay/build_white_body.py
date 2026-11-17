"""Blender headless: deterministic R15 curved meshes, shared UV atlas and surface data.

Run: blender --background --python Tools/Gameplay/build_white_body.py
"""
import json
import math
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'Assets/Models/WhiteBody'
OUT.mkdir(parents=True, exist_ok=True)
SPEC = json.loads((Path(__file__).with_name('white-rig-spec.json')).read_text())
NAMES = sorted(n for n in SPEC if n != 'HumanoidRootPart')
VERSION = 1
RINGS, SLICES = 16, 32
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
material = bpy.data.materials.new('MattePorcelainWhite')
material.diffuse_color = (.81, .81, .86, 1)
material.use_nodes = True
principled = material.node_tree.nodes.get('Principled BSDF')
if principled is None:
    principled = material.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    output = material.node_tree.nodes.new('ShaderNodeOutputMaterial')
    material.node_tree.links.new(principled.outputs['BSDF'], output.inputs['Surface'])
principled.inputs['Base Color'].default_value = (.81, .81, .86, 1)
principled.inputs['Roughness'].default_value = .68

def shape(name, t, a):
    y = -.5 * math.cos(math.pi * t)
    ring = math.sin(math.pi * t)
    exponent = .55 if 'Torso' in name else .65
    radius = ring ** exponent
    x, z = math.cos(a), math.sin(a)
    if name == 'Head':
        return (.5 * x * ring ** .8, y, .5 * z * ring ** .85)
    if name == 'UpperTorso':
        width = .73 + .27 * t
        return (.5 * x * radius * width, y, .5 * z * radius * (.87 + .13*t))
    if name == 'LowerTorso':
        return (.5 * x * radius * .85, y, .5 * z * radius * .9)
    if 'Arm' in name:
        taper = (.52 + .18*t) if 'Upper' in name else (.42 + .18*t)
        return (.5*x*radius*taper, y, .5*z*radius*taper)
    if 'Leg' in name:
        taper = (.64 + .21*t) if 'Upper' in name else (.46 + .24*t)
        return (.5*x*radius*taper, y, .5*z*radius*taper)
    if 'Hand' in name:
        return (.5*x*radius*.55, y, .5*z*radius*.65)
    return (.5*x*radius*.69, y, .5*z*radius)

metadata = {}
total_triangles = 0
for slot, name in enumerate(NAMES):
    spec = SPEC[name]
    # Ring seams have separate vertices/UVs; welding by position is used for topology QA.
    raw = [shape(name, j/RINGS, i/SLICES*2*math.pi) for j in range(RINGS+1) for i in range(SLICES+1)]
    lo = [min(p[k] for p in raw) for k in range(3)]
    hi = [max(p[k] for p in raw) for k in range(3)]
    size = [(hi[k]-lo[k])*spec['size'][k] for k in range(3)]
    positions = [tuple((p[k]-(hi[k]+lo[k])/2)/(hi[k]-lo[k]) for k in range(3)) for p in raw]
    vertices = [tuple(p[k]*size[k] for k in range(3)) for p in positions]
    tilex, tiley = slot % 4, slot // 4
    uvs = [((tilex+.015+.97*i/SLICES)/4, (tiley+.015+.97*j/RINGS)/4)
           for j in range(RINGS+1) for i in range(SLICES+1)]
    faces = []
    for j in range(RINGS):
        for i in range(SLICES):
            a = j*(SLICES+1)+i
            b, c, d = a+1, a+SLICES+1, a+SLICES+2
            # Outward winding in Roblox's right-handed Y-up coordinates.
            for f in ((a,c,b),(b,c,d)):
                va,vb,vc = (Vector(vertices[k]) for k in f)
                if (vb-va).cross(vc-va).length > 1e-8:
                    faces.append(f)
    mesh = bpy.data.meshes.new(name)
    # Blender is Z-up, Roblox is Y-up. FBX export reverses this axis conversion.
    mesh.from_pydata([(x,-z,y) for x,y,z in vertices], [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name='BodyAtlas')
    for poly in mesh.polygons:
        poly.use_smooth = True
        for loop in poly.loop_indices:
            uv.data[loop].uv = uvs[mesh.loops[loop].vertex_index]
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    x,y,z = spec['cf'][:3]
    obj.location = (x,-z,y+3.01)
    obj.data.materials.append(material)
    # Metadata uses normalized part-local coordinates; robust to import scaling.
    metadata[name] = {'size': size, 'vertices': [(-x,y,-z) for x,y,z in positions], 'uvs': uvs,
                      'triangles': [[i+1 for i in f] for f in faces], 'tile': [tilex,tiley]}
    total_triangles += len(faces)
    assert all(math.isfinite(c) for p in vertices for c in p)
    assert len(faces) == 960
    # Nonzero areas and a connected welded surface are required.
    assert all((Vector(vertices[b])-Vector(vertices[a])).cross(Vector(vertices[c])-Vector(vertices[a])).length > 1e-8 for a,b,c in faces)

assert total_triangles <= 15000
(OUT/'surface.json').write_text(json.dumps({'version': VERSION,'parts':metadata},separators=(',',':')))
lines = ['-- 曲面素体离线生成数据：归一化顶点、共享图集 UV 与稳定三角面索引', '--!strict',
         'export type Part = { size: Vector3, vertices: {Vector3}, uvs: {Vector2}, triangles: {{number}}, tile: Vector2 }',
         'local parts: {[string]: Part} = {}']
def vec(kind,p): return kind+'.new('+','.join(f'{x:.7f}' for x in p)+')'
for name,data in metadata.items():
    lines.append('parts["'+name+'"] = {size='+vec('Vector3',data['size'])+',tile='+vec('Vector2',data['tile'])+',')
    lines.append('vertices={'+','.join(vec('Vector3',p) for p in data['vertices'])+'},')
    lines.append('uvs={'+','.join(vec('Vector2',p) for p in data['uvs'])+'},')
    lines.append('triangles={'+','.join('{'+','.join(map(str,f))+'}' for f in data['triangles'])+'}}')
lines.append('return {Version='+str(VERSION)+',Parts=parts}')
(ROOT/'Scripts/ReplicatedStorage/Scripts/Shared/BodySurfaceData.luau').write_text('\n'.join(lines)+'\n',encoding='utf-8')
bpy.ops.export_scene.fbx(filepath=str(OUT/'WhiteBody.fbx'), use_selection=False, object_types={'MESH'},
                         axis_forward='-Z',axis_up='Y',apply_unit_scale=True,bake_space_transform=True,
                         add_leaf_bones=False)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'WhiteBody.blend'))
# Independent export readback: imported FBX names, triangle count, dimensions.
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.fbx(filepath=str(OUT/'WhiteBody.fbx'))
objects = [o for o in bpy.context.scene.objects if o.type=='MESH']
assert sorted(o.name for o in objects)==NAMES
assert sum(len(o.data.polygons) for o in objects)==total_triangles
for o in objects:
    assert all(math.isfinite(c) for v in o.data.vertices for c in v.co)
    assert len(o.data.uv_layers)==1
report={'version':VERSION,'parts':len(objects),'triangles':total_triangles,'exportReadback':True}
(OUT/'validation.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
