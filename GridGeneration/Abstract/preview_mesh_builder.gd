class_name PreviewMeshBuilder
extends RefCounted

## Utility class responsible for constructing dynamic meshes and 3D voxel wireframe outlines.

static func create_conforming_mesh(preview_size: Vector3i, base_gx: int, base_gz: int, heights: Dictionary) -> ArrayMesh:
	var array_mesh = ArrayMesh.new()
	
	for x_off in range(preview_size.x):
		for z_off in range(preview_size.z):
			var local_h: int = heights[Vector2i(x_off, z_off)]
			var col_bottom: float = (local_h + 1) * GData.CELL_SIZE
			var col_height: float = preview_size.y * GData.CELL_SIZE
			
			var start_x = (base_gx + x_off) * GData.CELL_SIZE
			var start_z = (base_gz + z_off) * GData.CELL_SIZE
			
			var center_pos = Vector3(
				start_x + GData.CELL_SIZE / 2.0,
				col_bottom + col_height / 2.0,
				start_z + GData.CELL_SIZE / 2.0
			)
			var box_dim = Vector3(GData.CELL_SIZE, col_height, GData.CELL_SIZE)
			
			_append_box_to_array_mesh(array_mesh, box_dim, center_pos)
			
	return array_mesh


static func _append_box_to_array_mesh(array_mesh: ArrayMesh, box_dim: Vector3, center_pos: Vector3) -> void:
	var box = BoxMesh.new()
	box.size = box_dim
	
	var st = SurfaceTool.new()
	st.create_from(box, 0)
	
	var mesh_array = st.commit_to_arrays()
	var verts: PackedVector3Array = mesh_array[Mesh.ARRAY_VERTEX]
	for i in range(verts.size()):
		verts[i] += center_pos
	mesh_array[Mesh.ARRAY_VERTEX] = verts
	
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_array)


static func build_conforming_wireframe(imm_mesh: ImmediateMesh, preview_size: Vector3i, base_gx: int, base_gz: int, heights: Dictionary) -> void:
	imm_mesh.clear_surfaces()
	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var occupied_voxels = _build_voxel_map(preview_size, heights)
	_draw_voxel_boundary_lines(imm_mesh, occupied_voxels, base_gx, base_gz)
	
	imm_mesh.surface_end()


static func _build_voxel_map(preview_size: Vector3i, heights: Dictionary) -> Dictionary:
	var occupied_voxels = {}
	for x_off in range(preview_size.x):
		for z_off in range(preview_size.z):
			var local_h: int = heights[Vector2i(x_off, z_off)]
			var bottom_tier: int = local_h + 1
			for y_off in range(preview_size.y):
				var tier = bottom_tier + y_off
				occupied_voxels[Vector3i(x_off, tier, z_off)] = true
	return occupied_voxels


static func _draw_voxel_boundary_lines(imm_mesh: ImmediateMesh, voxels: Dictionary, base_gx: int, base_gz: int) -> void:
	for voxel in voxels.keys():
		var lx: int = voxel.x
		var ty: int = voxel.y
		var lz: int = voxel.z
		
		var x0 = (base_gx + lx) * GData.CELL_SIZE
		var x1 = x0 + GData.CELL_SIZE
		var y0 = ty * GData.CELL_SIZE
		var y1 = y0 + GData.CELL_SIZE
		var z0 = (base_gz + lz) * GData.CELL_SIZE
		var z1 = z0 + GData.CELL_SIZE
		
		var n_fill = voxels.has(Vector3i(lx, ty, lz - 1))
		var s_fill = voxels.has(Vector3i(lx, ty, lz + 1))
		var w_fill = voxels.has(Vector3i(lx - 1, ty, lz))
		var e_fill = voxels.has(Vector3i(lx + 1, ty, lz))
		var d_fill = voxels.has(Vector3i(lx, ty - 1, lz))
		var u_fill = voxels.has(Vector3i(lx, ty + 1, lz))

		_draw_top_face_edges(imm_mesh, voxels, lx, ty, lz, x0, x1, y1, z0, z1, u_fill, n_fill, s_fill, w_fill, e_fill)
		_draw_bottom_face_edges(imm_mesh, voxels, lx, ty, lz, x0, x1, y0, z0, z1, d_fill, n_fill, s_fill, w_fill, e_fill)
		_draw_vertical_corner_edges(imm_mesh, x0, x1, y0, y1, z0, z1, n_fill, s_fill, w_fill, e_fill)


static func _draw_top_face_edges(imm_mesh: ImmediateMesh, voxels: Dictionary, lx: int, ty: int, lz: int, x0: float, x1: float, y1: float, z0: float, z1: float, u_fill: bool, n_fill: bool, s_fill: bool, w_fill: bool, e_fill: bool) -> void:
	if u_fill: return
	if not n_fill or voxels.has(Vector3i(lx, ty + 1, lz - 1)):
		_add_line(imm_mesh, Vector3(x0, y1, z0), Vector3(x1, y1, z0))
	if not s_fill or voxels.has(Vector3i(lx, ty + 1, lz + 1)):
		_add_line(imm_mesh, Vector3(x0, y1, z1), Vector3(x1, y1, z1))
	if not w_fill or voxels.has(Vector3i(lx - 1, ty + 1, lz)):
		_add_line(imm_mesh, Vector3(x0, y1, z0), Vector3(x0, y1, z1))
	if not e_fill or voxels.has(Vector3i(lx + 1, ty + 1, lz)):
		_add_line(imm_mesh, Vector3(x1, y1, z0), Vector3(x1, y1, z1))


static func _draw_bottom_face_edges(imm_mesh: ImmediateMesh, voxels: Dictionary, lx: int, ty: int, lz: int, x0: float, x1: float, y0: float, z0: float, z1: float, d_fill: bool, n_fill: bool, s_fill: bool, w_fill: bool, e_fill: bool) -> void:
	if d_fill: return
	if not n_fill or voxels.has(Vector3i(lx, ty - 1, lz - 1)):
		_add_line(imm_mesh, Vector3(x0, y0, z0), Vector3(x1, y0, z0))
	if not s_fill or voxels.has(Vector3i(lx, ty - 1, lz + 1)):
		_add_line(imm_mesh, Vector3(x0, y0, z1), Vector3(x1, y0, z1))
	if not w_fill or voxels.has(Vector3i(lx - 1, ty - 1, lz)):
		_add_line(imm_mesh, Vector3(x0, y0, z0), Vector3(x0, y0, z1))
	if not e_fill or voxels.has(Vector3i(lx + 1, ty - 1, lz)):
		_add_line(imm_mesh, Vector3(x1, y0, z0), Vector3(x1, y0, z1))


static func _draw_vertical_corner_edges(imm_mesh: ImmediateMesh, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, n_fill: bool, s_fill: bool, w_fill: bool, e_fill: bool) -> void:
	if not w_fill and not n_fill:
		_add_line(imm_mesh, Vector3(x0, y0, z0), Vector3(x0, y1, z0))
	if not e_fill and not n_fill:
		_add_line(imm_mesh, Vector3(x1, y0, z0), Vector3(x1, y1, z0))
	if not w_fill and not s_fill:
		_add_line(imm_mesh, Vector3(x0, y0, z1), Vector3(x0, y1, z1))
	if not e_fill and not s_fill:
		_add_line(imm_mesh, Vector3(x1, y0, z1), Vector3(x1, y1, z1))


static func build_standard_box_wireframe(imm_mesh: ImmediateMesh, size: Vector3, is_remove_mode: bool) -> void:
	imm_mesh.clear_surfaces()
	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var ext = size / 2.0
	_draw_cage_skeleton_lines(imm_mesh, ext)
	
	if is_remove_mode:
		_draw_tactical_hash_lines(imm_mesh, ext)
		
	imm_mesh.surface_end()


static func _draw_cage_skeleton_lines(imm_mesh: ImmediateMesh, ext: Vector3) -> void:
	# Top Plane
	_add_line(imm_mesh, Vector3(-ext.x,  ext.y, -ext.z), Vector3( ext.x,  ext.y, -ext.z))
	_add_line(imm_mesh, Vector3( ext.x,  ext.y, -ext.z), Vector3( ext.x,  ext.y,  ext.z))
	_add_line(imm_mesh, Vector3( ext.x,  ext.y,  ext.z), Vector3(-ext.x,  ext.y,  ext.z))
	_add_line(imm_mesh, Vector3(-ext.x,  ext.y,  ext.z), Vector3(-ext.x,  ext.y, -ext.z))
	# Bottom Plane
	_add_line(imm_mesh, Vector3(-ext.x, -ext.y, -ext.z), Vector3( ext.x, -ext.y, -ext.z))
	_add_line(imm_mesh, Vector3( ext.x, -ext.y, -ext.z), Vector3( ext.x, -ext.y,  ext.z))
	_add_line(imm_mesh, Vector3( ext.x, -ext.y,  ext.z), Vector3(-ext.x, -ext.y,  ext.z))
	_add_line(imm_mesh, Vector3(-ext.x, -ext.y,  ext.z), Vector3(-ext.x, -ext.y, -ext.z))
	# Vertical Connectors
	_add_line(imm_mesh, Vector3(-ext.x, -ext.y, -ext.z), Vector3(-ext.x,  ext.y, -ext.z))
	_add_line(imm_mesh, Vector3( ext.x, -ext.y, -ext.z), Vector3( ext.x,  ext.y, -ext.z))
	_add_line(imm_mesh, Vector3( ext.x, -ext.y,  ext.z), Vector3( ext.x,  ext.y,  ext.z))
	_add_line(imm_mesh, Vector3(-ext.x, -ext.y,  ext.z), Vector3(-ext.x,  ext.y,  ext.z))


static func _draw_tactical_hash_lines(imm_mesh: ImmediateMesh, ext: Vector3) -> void:
	# Top Face (+Y)
	_add_line(imm_mesh, Vector3(-ext.x,  ext.y, -ext.z), Vector3( ext.x,  ext.y,  ext.z))
	_add_line(imm_mesh, Vector3( ext.x,  ext.y, -ext.z), Vector3(-ext.x,  ext.y,  ext.z))
	
	# Bottom Face (-Y)
	_add_line(imm_mesh, Vector3(-ext.x, -ext.y, -ext.z), Vector3( ext.x, -ext.y,  ext.z))
	_add_line(imm_mesh, Vector3( ext.x, -ext.y, -ext.z), Vector3(-ext.x, -ext.y,  ext.z))
	
	# Front Face (+Z)
	_add_line(imm_mesh, Vector3(-ext.x, -ext.y,  ext.z), Vector3( ext.x,  ext.y,  ext.z))
	_add_line(imm_mesh, Vector3( ext.x, -ext.y,  ext.z), Vector3(-ext.x,  ext.y,  ext.z))
	
	# Back Face (-Z)
	_add_line(imm_mesh, Vector3(-ext.x, -ext.y, -ext.z), Vector3( ext.x,  ext.y, -ext.z))
	_add_line(imm_mesh, Vector3( ext.x, -ext.y, -ext.z), Vector3(-ext.x,  ext.y, -ext.z))
	
	# Right Face (+X)
	_add_line(imm_mesh, Vector3( ext.x, -ext.y, -ext.z), Vector3( ext.x,  ext.y,  ext.z))
	_add_line(imm_mesh, Vector3( ext.x, -ext.y,  ext.z), Vector3( ext.x,  ext.y, -ext.z))
	
	# Left Face (-X)
	_add_line(imm_mesh, Vector3(-ext.x, -ext.y, -ext.z), Vector3(-ext.x,  ext.y,  ext.z))
	_add_line(imm_mesh, Vector3(-ext.x, -ext.y,  ext.z), Vector3(-ext.x,  ext.y, -ext.z))


static func _add_line(imm_mesh: ImmediateMesh, p1: Vector3, p2: Vector3) -> void:
	imm_mesh.surface_add_vertex(p1)
	imm_mesh.surface_add_vertex(p2)
