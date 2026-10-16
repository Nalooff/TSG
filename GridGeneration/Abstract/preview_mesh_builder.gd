class_name PreviewMeshBuilder
extends RefCounted

## Utility class responsible for constructing dynamic meshes and 3D voxel wireframe outlines.



## Builds a snake-like 3D arrow: tubes joined by round joints, with a cone head on the last point.
## `tile_points` are the world-space points the snake passes through (one per tile, start first).
## The returned Node3D holds its children in the same space as the points, so keep its parent at identity.
static func create_path_snake(tile_points: Array[Vector3], color: Color, tube_radius: float = 0.18, head_radius: float = 0.45, head_length: float = 0.8) -> Node3D:
	var root := Node3D.new()
	root.name = "PathSnake"
	if tile_points.size() < 2:
		return root

	# Opaque on purpose: overlapping parts stay invisible, so joints look seamless
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35

	var pts := _expand_height_corners(tile_points)
	var last := pts.size() - 1

	for i in range(last):
		root.add_child(_make_snake_sphere(pts[i], tube_radius, mat))   # round joint (also rounds the tail)
		root.add_child(_make_snake_tube(pts[i], pts[i + 1], tube_radius, mat))

	var dir := (pts[last] - pts[last - 1]).normalized()
	root.add_child(_make_snake_head(pts[last], dir, head_radius, head_length, mat))
	return root


## Inserts a corner point on every height change so the tube rises at the current tile
## (climb) or drops at the next tile (descent), never cutting through a wall.
static func _expand_height_corners(tile_points: Array[Vector3]) -> Array[Vector3]:
	var pts: Array[Vector3] = [tile_points[0]]
	for i in range(1, tile_points.size()):
		var p: Vector3 = pts.back()
		var q: Vector3 = tile_points[i]
		if q.y > p.y + 0.001:
			pts.append(Vector3(p.x, q.y, p.z))
		elif q.y < p.y - 0.001:
			pts.append(Vector3(q.x, p.y, q.z))
		pts.append(q)
	return pts


static func _make_snake_tube(a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var dir := b - a
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = dir.length()
	mesh.radial_segments = 12
	mesh.rings = 1
	return _make_oriented_mesh(mesh, mat, (a + b) * 0.5, dir.normalized())


static func _make_snake_sphere(pos: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _make_oriented_mesh(mesh, mat, pos, Vector3.UP)


static func _make_snake_head(tip_point: Vector3, dir: Vector3, radius: float, length: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0   # apex
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.rings = 1
	# Shifted back so the apex ends just past the tile center
	return _make_oriented_mesh(mesh, mat, tip_point - dir * length * 0.3, dir)


## Creates a MeshInstance3D at `pos` (local space) with its Y axis aligned to `up_dir`.
static func _make_oriented_mesh(mesh: Mesh, mat: Material, pos: Vector3, up_dir: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var orient: Basis
	if up_dir.is_equal_approx(Vector3.DOWN):
		orient = Basis(Vector3.RIGHT, PI)
	else:
		orient = Basis(Quaternion(Vector3.UP, up_dir))
	mi.transform = Transform3D(orient, pos)
	return mi


## Creates a flat MeshInstance3D plane tile for highlighting board cells.
static func create_tile_highlight(size: Vector2, color: Color, custom_material: Material = null) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = size
	mesh_instance.mesh = plane_mesh
	
	if custom_material:
		mesh_instance.material_override = custom_material
	else:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_instance.material_override = material
	
	return mesh_instance


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
