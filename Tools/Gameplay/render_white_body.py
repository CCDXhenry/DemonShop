"""Render the authored body in four views with the final arm placement."""
from pathlib import Path
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'Assets/Models/WhiteBody'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'WhiteBody.blend'))
for obj in bpy.context.scene.objects:
    if obj.type=='MESH' and ('Arm' in obj.name or 'Hand' in obj.name):
        obj.location.x += .3 if obj.name.startswith('Left') else -.3
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=24
scene.render.resolution_x=640
scene.render.resolution_y=640
scene.render.resolution_percentage=100
scene.world.color=(.16,.18,.22)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.02))
floor=bpy.context.object
mat=bpy.data.materials.new('Backdrop')
mat.diffuse_color=(.07,.09,.13,1)
floor.data.materials.append(mat)
for location,energy,size in [((4,-5,8),900,5),((-4,-1,5),600,4),((1,4,6),900,3)]:
    bpy.ops.object.light_add(type='AREA',location=location)
    light=bpy.context.object
    light.data.energy=energy
    light.data.shape='DISK'
    light.data.size=size
    light.rotation_euler=(Vector((0,0,2.5))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add()
camera=bpy.context.object
camera.data.type='ORTHO'
camera.data.ortho_scale=6.4
scene.camera=camera
for name,location in [('perspective_front',(7,-10,6)),('side',(10,0,3)),('perspective_back',(-7,10,6)),('top',(0,-.01,12))]:
    camera.location=location
    camera.rotation_euler=(Vector((0,0,2.6))-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(OUT/(name+'.png'))
    bpy.ops.render.render(write_still=True)
