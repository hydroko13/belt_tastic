package main

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/noise"
import "core:math/rand"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

TPS :: 20


Building_Tile_Data :: struct {
	x:            int,
	y:            int,
	sprite_index: int,
	type:         string,
}

Registered_Building :: struct {
	ident:               string,
	spritesheet_width:   int,
	spritesheet_texture: rl.Texture,
	tiles:               [dynamic]Building_Tile_Data,
}

Building_Data :: struct {
	ident:             string,
	spritesheet_width: int,
	tiles:             [dynamic]Building_Tile_Data,
}

load :: proc(building_registry: ^[dynamic]Registered_Building) -> bool {
	cwd, err := os.get_working_directory(context.allocator)
	if err != os.General_Error.None {
		return false
	}


	defer delete(cwd)

	buildings_dir, join_err := os.join_path({cwd, "res", "buildings"}, context.allocator)

	if join_err != .None {
		return false
	}

	defer delete(buildings_dir)

	buildings_dir_handle, open_err := os.open(buildings_dir)

	if open_err != os.General_Error.None {
		return false
	}

	defer os.close(buildings_dir_handle)

	file_infos, read_err := os.read_dir(buildings_dir_handle, -1, context.allocator)

	if read_err != os.General_Error.None {
		return false
	}

	defer os.file_info_slice_delete(file_infos, context.allocator)

	for file in file_infos {
		if file.type == .Regular {
			filename := file.name
			file_name_no_ext: string

			parts, split_err := strings.split(filename, ".")

			if split_err != .None {
				return false
			}
			is_json := false

			for part, i in parts {
				if i == len(parts) - 1 {
					if part == "json" {
						is_json = true
					}
				}
				if i == 0 {
					file_name_no_ext = part
				}
			}

			if is_json { 	// read building json file
				building_file_path, join_err := os.join_path(
					{cwd, "res", "buildings", filename},
					context.allocator,
				)

				if join_err != .None {
					return false
				}

				concat_result, _ := strings.concatenate({file_name_no_ext, ".png"})


				building_image_Path, join_err_img := os.join_path(
					{cwd, "res", "buildings", concat_result},
					context.allocator,
				)

				delete(concat_result)

				file_contents, file_err := os.read_entire_file(
					building_file_path,
					context.allocator,
				)

				if file_err == os.General_Error.None {
					data: Building_Data

					json_parse_err := json.unmarshal(transmute([]u8)file_contents, &data)

					if json_parse_err == nil {

						new_building: Registered_Building

						new_building.ident = data.ident
						new_building.spritesheet_width = data.spritesheet_width
						cstr := strings.clone_to_cstring(building_image_Path)
						
						new_building.spritesheet_texture = rl.LoadTexture(cstr)
						delete(cstr)
						delete(building_image_Path)

						new_building.tiles = data.tiles


						append(building_registry, new_building)


					}


				}


				delete(file_contents)


			}

			delete(parts)


		}
	}


	return true

}


frame_update :: proc(frame_delta: f32, camera: ^rl.Camera2D, last_mp: rl.Vector2, mp: rl.Vector2) {

	mouse_scroll_value := rl.GetMouseWheelMoveV().y
	world_mp := rl.GetScreenToWorld2D(mp, camera^)

	if mouse_scroll_value < 0 {
		camera.zoom -= 1
		if camera.zoom < 0.1 {
			camera.zoom = 0.1
		}
	} else if mouse_scroll_value > 0 {

		camera.zoom += 1

	}

	deltax := mp.x - last_mp.x
	deltay := mp.y - last_mp.y


	if rl.IsMouseButtonDown(rl.MouseButton.MIDDLE) {


		camera.target.x -= deltax * 1
		camera.target.y -= deltay * 1

	}


}

Place_Mode :: enum {
	Belt,
	Building,
}


Belt_Place_Mode :: enum {
	PlacedA,
	PendingA,
}

Travelling_Item :: struct {
	item_id:         int,
	travel_progress: f32,
}

Belt :: struct {
	point_a:          rl.Vector2,
	point_b:          rl.Vector2,
	items_travelling: [dynamic]Travelling_Item,
}

Placed_Building :: struct {
	building_idx: int,
	x:            int,
	y:            int,
	storage:      [dynamic]int, // dyn list of item ids
	user_timer:   f32,
}

World_Item :: struct {
	tile_pos: [2]int,
	item_id:  int,
}

World_Chunk :: struct {
	tile_data: [16 * 16]u8,
}

Chunk_Pos :: struct {
	x: int,
	y: int,
}


gen_chunk :: proc(world_chunks: ^map[Chunk_Pos]World_Chunk, pos: Chunk_Pos) {
	_, exists := world_chunks[pos]
	if !exists {
		chunk := World_Chunk {
			tile_data = [16 * 16]u8{},
		}


		for x in 0 ..< 16 {
			for y in 0 ..< 16 {
				height := int(
					noise.noise_2d(
						1500,
						{(f64(x) + f64(pos.x * 16)) / 24.0, (f64(y) + f64(pos.y * 16)) / 24.0},
					) *
					15.0,
				)

				if height > 5.0 {
					chunk.tile_data[x * 16 + y] = 1
				} else {
					chunk.tile_data[x * 16 + y] = 0
				}

			}
		}


		world_chunks[pos] = chunk
	}

}

gen_chunks_at :: proc(world_chunks: ^map[Chunk_Pos]World_Chunk, pos: Chunk_Pos) {
	gen_chunk(world_chunks, pos)
	gen_chunk(world_chunks, Chunk_Pos{x = pos.x + 1, y = pos.y})
	gen_chunk(world_chunks, Chunk_Pos{x = pos.x - 1, y = pos.y})
	gen_chunk(world_chunks, Chunk_Pos{x = pos.x, y = pos.y + 1})
	gen_chunk(world_chunks, Chunk_Pos{x = pos.x, y = pos.y - 1})
}

is_edge_chunk :: proc(world_chunks: ^map[Chunk_Pos]World_Chunk, pos: Chunk_Pos) -> bool {
	_, exists := world_chunks[pos]
	if exists {
		_, exists_left := world_chunks[Chunk_Pos{x = pos.x - 1, y = pos.y}]
		_, exists_right := world_chunks[Chunk_Pos{x = pos.x + 1, y = pos.y}]
		_, exists_up := world_chunks[Chunk_Pos{x = pos.x, y = pos.y - 1}]
		_, exists_down := world_chunks[Chunk_Pos{x = pos.x, y = pos.y + 1}]
		if (!exists_left) || (!exists_right) || (!exists_up) || (!exists_down) {
			return true
		} else {
			return false
		}
	} else {
		return false
	}
}

main :: proc() {


	speed_multiply := 1.0
	blip_sound_cooldown: f32 = 0.0
	rl.InitWindow(1200, 800, "Belt-tastic")
	defer rl.CloseWindow()


	rl.InitAudioDevice()

	music := rl.LoadMusicStream("res/audio/IndustrialZone.ogg")

	rl.SetMusicVolume(music, 1.0)

	rl.PlayMusicStream(music)

	rl.ToggleFullscreen()

	blipSound := rl.LoadSound("res/audio/blipSelect.wav")
	defer rl.UnloadSound(blipSound)

	blipSound2 := rl.LoadSound("res/audio/blipSelect2.wav")
	defer rl.UnloadSound(blipSound2)

	building_registry := make([dynamic]Registered_Building)
	defer {
		for building in building_registry {
			delete(building.ident)
			delete(building.tiles)
			rl.UnloadTexture(building.spritesheet_texture)
		}
		delete(building_registry)
	}

	
	item_registry := make([dynamic]Registered_Item)
	defer {
		for item in item_registry {
			rl.UnloadTexture(item.texture)
		}
		delete(item_registry)
	}

	if !load(&building_registry) {
		return
	}

	if !load_items(&item_registry) {
		return
	}

	building_being_placed_idx := 1

	place_mode := Place_Mode.Building
	belt_place_mode := Belt_Place_Mode.PendingA
	belt_a_pos: [2]int

	camera := rl.Camera2D{}
	camera.rotation = 0.0
	camera.zoom = 1.0


	tick_delta := 1.0 / TPS
	tick_timer := 0.0

	mouse_pos := rl.GetMousePosition()

	placed_belts := make([dynamic]Belt)
	defer {
		for belt in placed_belts {
			delete(belt.items_travelling)
		}
		delete(placed_belts)
	}

	placed_buildings := make([dynamic]Placed_Building)
	defer {
		for building in placed_buildings {
			delete(building.storage)
		}
		delete(placed_buildings)
	}

	world_items := make([dynamic]World_Item)
	defer delete(world_items)

	tile_x_last, tile_y_last := 0, 0

	world_chunks := make(map[Chunk_Pos]World_Chunk)
	defer delete(world_chunks)


	gen_chunks_at(&world_chunks, Chunk_Pos{x = 0, y = 0})


	current_goal: Goal = empty_goal()
	
	defer delete_goal(&current_goal)

	set_goal_to_chunk(&current_goal, -1, 0)

	
	for !rl.WindowShouldClose() {

		camera.offset = {f32(rl.GetScreenWidth()) / 2, f32(rl.GetScreenHeight()) / 2}

		rl.UpdateMusicStream(music)

		last_mouse_pos := mouse_pos
		mouse_pos = rl.GetMousePosition()


		delta := rl.GetFrameTime()

		tick_timer += f64(delta)

		if tick_timer > tick_delta / speed_multiply {
			//on_tick(f32(tick_delta), &camera)


			producers_tiles := make([dynamic][2]int)
			defer delete(producers_tiles)


			for &world_building in placed_buildings {
				building := building_registry[world_building.building_idx]

				if building.ident == "depot" {

					// find input tile

					depot_input_tile_pos := [2]int{0, 0}

					found_input := false
					for tile in building.tiles {
						if tile.type == "input" {
							if !found_input {
								depot_input_tile_pos.x = world_building.x + tile.x
								depot_input_tile_pos.y = world_building.y + tile.y
								found_input = true
							}
						}
					}


					// check world items that can be sucked into the input tile
					// SUCK IT IN
					if len(world_items) > 0 {
						if len(world_building.storage) < 64 {
							for i := len(world_items) - 1; i >= 0; i -= 1 {
								world_item := world_items[i]
								if world_item.tile_pos == depot_input_tile_pos {
									append(&world_building.storage, world_item.item_id)
									ordered_remove(&world_items, i)
								}
							}
						}
					}


					// now output tile
					if len(world_building.storage) > 0 {
						random_item_idx := rand.int_range(0, len(world_building.storage))
						item := world_building.storage[random_item_idx]

						depot_output_tile_pos := [2]int{0, 0}

						found_output := false
						for tile in building.tiles {
							if tile.type == "output" {
								if !found_output {
									depot_output_tile_pos.x = world_building.x + tile.x
									depot_output_tile_pos.y = world_building.y + tile.y
									found_output = true
								}
							}
						}

						found_other_item_in_output := false

						for other_item in world_items {
							if other_item.tile_pos == depot_output_tile_pos {
								found_other_item_in_output = true
							}
						}

						if !found_other_item_in_output {
							new_world_item := World_Item {
								tile_pos = depot_output_tile_pos,
								item_id  = 0,
							}
							append(&world_items, new_world_item)
							ordered_remove(&world_building.storage, random_item_idx)
						}


					}


				}

				if building.ident == "collector" {

					// find input tile

					depot_input_tile_pos := [2]int{0, 0}

					found_input := false
					for tile in building.tiles {
						if tile.type == "input" {
							if !found_input {
								depot_input_tile_pos.x = world_building.x + tile.x
								depot_input_tile_pos.y = world_building.y + tile.y
								found_input = true
							}
						}
					}


					// check world items that can be sucked into the input tile
					// SUCK IT IN
					if len(world_items) > 0 {
						if len(world_building.storage) < 64 {
							for i := len(world_items) - 1; i >= 0; i -= 1 {
								world_item := world_items[i]
								if world_item.tile_pos == depot_input_tile_pos {
									ordered_remove(&world_items, i)
								}
							}
						}
					}


				}

				if building.ident == "miner" {

					world_building.user_timer += f32(tick_delta)
					if world_building.user_timer > 0.5 {


						if len(world_building.storage) < 64 {
							append(&world_building.storage, 0)
						}


						world_building.user_timer = 0.0
					}


					// now output tile
					if len(world_building.storage) > 0 {
						random_item_idx := rand.int_range(0, len(world_building.storage))
						item := world_building.storage[random_item_idx]


						miner_output_tile_pos := [2]int{0, 0}

						found_output := false
						for tile in building.tiles {
							if tile.type == "output" {
								if !found_output {
									miner_output_tile_pos.x = world_building.x + tile.x
									miner_output_tile_pos.y = world_building.y + tile.y
									found_output = true
								}
							}
						}

						found_other_item_in_output := false

						for other_item in world_items {
							if other_item.tile_pos == miner_output_tile_pos {
								found_other_item_in_output = true
							}
						}

						if !found_other_item_in_output {
							new_world_item := World_Item {
								tile_pos = miner_output_tile_pos,
								item_id  = 0,
							}
							append(&world_items, new_world_item)
							ordered_remove(&world_building.storage, random_item_idx)
						}


					}


				}

				if building.ident == "splitter" {

					splitter_input_tile_pos := [2]int{0, 0}

					found_input := false
					for tile in building.tiles {
						if tile.type == "input" {
							if !found_input {
								splitter_input_tile_pos.x = world_building.x + tile.x
								splitter_input_tile_pos.y = world_building.y + tile.y
								found_input = true
							}
						}
					}


					// check world items that can be sucked into the input tile
					// SUCK IT IN
					if len(world_items) > 0 {
						if len(world_building.storage) < 1 {
							for i := len(world_items) - 1; i >= 0; i -= 1 {
								world_item := world_items[i]
								if world_item.tile_pos == splitter_input_tile_pos {
									append(&world_building.storage, world_item.item_id)
									ordered_remove(&world_items, i)
								}
							}
						}
					}


					// now output tile
					if len(world_building.storage) > 0 {
						random_item_idx := rand.int_range(0, len(world_building.storage))
						item := world_building.storage[random_item_idx]


						miner_output_tile_pos1 := [2]int{0, 0}
						miner_output_tile_pos2 := [2]int{0, 0}


						found_outputs := 0
						for tile in building.tiles {
							if tile.type == "output" {
								if found_outputs < 2 {
									if found_outputs == 1 {
										miner_output_tile_pos2.x = world_building.x + tile.x
										miner_output_tile_pos2.y = world_building.y + tile.y
									} else {
										miner_output_tile_pos1.x = world_building.x + tile.x
										miner_output_tile_pos1.y = world_building.y + tile.y
									}

									found_outputs += 1
								}
							}
						}

						found_other_item_in_output1 := false

						for other_item in world_items {
							if other_item.tile_pos == miner_output_tile_pos1 {
								found_other_item_in_output1 = true
							}
						}

						found_other_item_in_output2 := false

						for other_item in world_items {
							if other_item.tile_pos == miner_output_tile_pos2 {
								found_other_item_in_output2 = true
							}
						}

						if (!found_other_item_in_output1) && (!found_other_item_in_output2) {

							if world_building.user_timer == 0.0 {
								world_building.user_timer = 1.0
							}

							if world_building.user_timer > 0.0 {
								new_world_item := World_Item {
									tile_pos = miner_output_tile_pos1,
									item_id  = 0,
								}
								append(&world_items, new_world_item)
								ordered_remove(&world_building.storage, random_item_idx)
							} else if world_building.user_timer < 0.0 {
								new_world_item := World_Item {
									tile_pos = miner_output_tile_pos2,
									item_id  = 0,
								}
								append(&world_items, new_world_item)
								ordered_remove(&world_building.storage, random_item_idx)
							}


							world_building.user_timer = -world_building.user_timer
							// we will use the user_timer variable as a way to store the alternate state even if its not a timer

						}
						else if (!found_other_item_in_output1) && (found_other_item_in_output2) {

							new_world_item := World_Item {
								tile_pos = miner_output_tile_pos1,
								item_id  = 0,
							}
							append(&world_items, new_world_item)
							ordered_remove(&world_building.storage, random_item_idx)



							// we will use the user_timer variable as a way to store the alternate state even if its not a timer

						}
						else if (found_other_item_in_output1) && (!found_other_item_in_output2) {

							new_world_item := World_Item {
								tile_pos = miner_output_tile_pos2,
								item_id  = 0,
							}
							append(&world_items, new_world_item)
							ordered_remove(&world_building.storage, random_item_idx)



							// we will use the user_timer variable as a way to store the alternate state even if its not a timer

						}


					}


				}


			}


			for &belt in placed_belts {
				distance := math.sqrt(
					math.pow((belt.point_a.x * 16 + 8) - (belt.point_b.x * 16 + 8), 2.0) +
					math.pow((belt.point_a.y * 16 + 8) - (belt.point_b.y * 16 + 8), 2.0),
				)
				for &item, idx1 in belt.items_travelling {
					minimum_travel_progress_infront: f32 = 2.0
					for &other_item, idx2 in belt.items_travelling {
						if idx2 != idx1 {
							if other_item.travel_progress < minimum_travel_progress_infront {
								if other_item.travel_progress > item.travel_progress {
									minimum_travel_progress_infront = other_item.travel_progress
								}
							}
						}
					}

					if minimum_travel_progress_infront == 2.0 {
						item.travel_progress += (60.0 * f32(tick_delta)) / distance
					} else if !(((minimum_travel_progress_infront - item.travel_progress) *
							   distance) <
						   11) {
						item.travel_progress += (60.0 * f32(tick_delta)) / distance
					}

				}

				for i := len(belt.items_travelling) - 1; i >= 0; i -= 1 {
					item := &belt.items_travelling[i]


					if item.travel_progress > 1.0 {
						item.travel_progress = 1.0

						tile_pos := [2]int{int(belt.point_b.x), int(belt.point_b.y)}
						blocked_by_item := false

						for world_item in world_items {
							if world_item.tile_pos == tile_pos {
								blocked_by_item = true
							}
						}

						if !blocked_by_item {
							new_world_item := World_Item {
								tile_pos = tile_pos,
								item_id  = 0,
							}
							append(&world_items, new_world_item)
							unordered_remove(&belt.items_travelling, i)
						}

					}
				}
			}

			for &belt in placed_belts {
				a_tile_pos := [2]int{int(belt.point_a.x), int(belt.point_a.y)}
				b_tile_pos := [2]int{int(belt.point_b.x), int(belt.point_b.y)}

				found_at_start := false
				for item in belt.items_travelling {
					if item.travel_progress == 0.0 {
						found_at_start = true
					}
				}

				if !found_at_start {
					for i := len(world_items) - 1; i >= 0; i -= 1 {
						world_item := world_items[i]
						if world_item.tile_pos == a_tile_pos {

							append(
								&belt.items_travelling,
								Travelling_Item {
									item_id = world_item.item_id,
									travel_progress = 0.0,
								},
							)

							ordered_remove(&world_items, i)
						}
					}
				}


			}


			tick_timer = 0.0
		}


		frame_update(delta, &camera, last_mouse_pos, mouse_pos)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		rl.BeginMode2D(camera)

		if rl.IsKeyPressed(.SPACE) {
			switch place_mode {
			case .Belt:
				place_mode = .Building
			case .Building:
				place_mode = .Belt
			}
			rl.PlaySound(blipSound2)
		}

		if rl.IsKeyPressed(.Q) {
			if place_mode == .Building {
				building_being_placed_idx += 1
				if building_being_placed_idx > len(building_registry) - 1 {
					building_being_placed_idx = 0
				}
			}
			rl.PlaySound(blipSound2)
		}
		if rl.IsKeyPressed(.P) {
			if place_mode == .Building {
				building_being_placed_idx -= 1
				if building_being_placed_idx < 0 {
					building_being_placed_idx = len(building_registry) - 1
				}
			}
			rl.PlaySound(blipSound2)
		}

		world_pos_corner1 := rl.GetScreenToWorld2D({-(16.0 * 16.0), -(16.0 * 16.0)}, camera)
		world_pos_corner2 := rl.GetScreenToWorld2D(
			{f32(rl.GetScreenWidth()) + (16.0 * 16.0), f32(rl.GetScreenHeight()) + (16.0 * 16.0)},
			camera,
		)

		world_pos_corner1.x = math.floor(world_pos_corner1.x / (16.0 * 16.0))
		world_pos_corner1.y = math.floor(world_pos_corner1.y / (16.0 * 16.0))
		world_pos_corner2.x = math.floor(world_pos_corner2.x / (16.0 * 16.0))
		world_pos_corner2.y = math.floor(world_pos_corner2.y / (16.0 * 16.0))


		for chunk_x in world_pos_corner1.x ..= world_pos_corner2.x {
			for chunk_y in world_pos_corner1.y ..= world_pos_corner2.y {
				chunk_pos := Chunk_Pos {
					x = int(chunk_x),
					y = int(chunk_y),
				}
				chunk, ok := world_chunks[chunk_pos]
				if ok {
					if is_edge_chunk(&world_chunks, chunk_pos) {
						for x in 0 ..< 16 {
							for y in 0 ..< 16 {
								tile := chunk.tile_data[x * 16 + y]
								if tile == 0 {
									rl.DrawRectangle(
										i32(chunk_pos.x * (16 * 16)) + i32(x * 16),
										i32(chunk_pos.y * (16 * 16)) + i32(y * 16),
										16,
										16,
										rl.Fade(rl.GREEN, 0.2),
									)
								} else if tile == 1 {
									rl.DrawRectangle(
										i32(chunk_pos.x * (16 * 16)) + i32(x * 16),
										i32(chunk_pos.y * (16 * 16)) + i32(y * 16),
										16,
										16,
										rl.Fade(rl.DARKBLUE, 0.2)
									)
								}

							}
						}
					} else {
						for x in 0 ..< 16 {
							for y in 0 ..< 16 {
								tile := chunk.tile_data[x * 16 + y]
								if tile == 0 {
									rl.DrawRectangle(
										i32(chunk_pos.x * (16 * 16)) + i32(x * 16),
										i32(chunk_pos.y * (16 * 16)) + i32(y * 16),
										16,
										16,
										rl.GREEN,
									)
								} else if tile == 1 {
									rl.DrawRectangle(
										i32(chunk_pos.x * (16 * 16)) + i32(x * 16),
										i32(chunk_pos.y * (16 * 16)) + i32(y * 16),
										16,
										16,
										rl.DARKBLUE,
									)
								}

							}
						}
						for x in 0 ..< 16 {
							for y in 0 ..< 16 {
								rl.DrawLine(
									i32(chunk_pos.x * (16 * 16)),
									i32(chunk_pos.y * (16 * 16)) + i32(y * 16),
									i32(chunk_pos.x * (16 * 16)) + (16 * 16),
									i32(chunk_pos.y * (16 * 16)) + i32(y * 16),
									rl.GRAY,
								)
							}
							rl.DrawLine(
								i32(chunk_pos.x * (16 * 16)),
								i32(chunk_pos.y * (16 * 16)) + i32(16 * 16),
								i32(chunk_pos.x * (16 * 16)) + (16 * 16),
								i32(chunk_pos.y * (16 * 16)) + i32(16 * 16),
								rl.GRAY,
							)

							rl.DrawLine(
								i32(chunk_pos.x * (16 * 16)) + i32(x * 16),
								i32(chunk_pos.y * (16 * 16)),
								i32(chunk_pos.x * (16 * 16)) + i32(x * 16),
								i32(chunk_pos.y * (16 * 16)) + (16 * 16),
								rl.GRAY,
							)
						}
						rl.DrawLine(
							i32(chunk_pos.x * (16 * 16)) + i32(16 * 16),
							i32(chunk_pos.y * (16 * 16)),
							i32(chunk_pos.x * (16 * 16)) + i32(16 * 16),
							i32(chunk_pos.y * (16 * 16)) + (16 * 16),
							rl.GRAY,
						)
					}


				}

			}
		}

		for building_placed in placed_buildings {
			building := building_registry[building_placed.building_idx]

			for tile in building.tiles {
				rl.DrawTextureRec(
					building.spritesheet_texture,
					rl.Rectangle{x = f32(tile.sprite_index * 16), y = 0, width = 16, height = 16},
					{
						(f32(building_placed.x) + f32(tile.x)) * 16.0,
						(f32(building_placed.y) + f32(tile.y)) * 16.0,
					},
					rl.WHITE,
				)

			}
		}

		for belt in placed_belts {
			length_to_mouse_tile := math.sqrt(
				math.pow(f32(belt.point_a.x * 16) + 8.0 - (belt.point_b.x * 16.0 + 8.0), 2.0) +
				math.pow(f32(belt.point_a.y * 16 + 8.0) - (belt.point_b.y * 16.0 + 8.0), 2.0),
			)
			belt_thickness: f32 = 12.0
			belt_center: rl.Vector2

			belt_center.x = (f32(belt.point_a.x * 16.0 + 8.0) + (belt.point_b.x * 16.0 + 8.0)) / 2
			belt_center.y = (f32(belt.point_a.y * 16.0 + 8.0) + (belt.point_b.y * 16.0 + 8.0)) / 2

			direc := math.to_degrees(
				math.atan2(
					f32(belt.point_a.y * 16 + 8.0) - (belt.point_b.y * 16. + 8.0),
					f32(belt.point_a.x * 16 + 8.0) - (belt.point_b.x * 16.0 + 8.0),
				),
			)

			rl.DrawRectanglePro(
				rl.Rectangle{belt_center.x, belt_center.y, length_to_mouse_tile, belt_thickness},
				{length_to_mouse_tile / 2.0, belt_thickness / 2.0},
				direc,
				rl.GRAY,
			)

		}

		for &belt in placed_belts {
			for item in belt.items_travelling {
				point_a := [2]f32{belt.point_a.x * 16 + 8.0, belt.point_a.y * 16 + 8.0}
				point_b := [2]f32{belt.point_b.x * 16 + 8.0, belt.point_b.y * 16 + 8.0}
				dx := point_b.x - point_a.x
				dy := point_b.y - point_a.y

				cx, cy := i32(point_a.x + (dx * item.travel_progress)), i32(point_a.y + (dy * item.travel_progress))
				
				for registered_item in item_registry {
					if registered_item.id == item.item_id {
						rl.DrawTexture(
							registered_item.texture,
							cx - 8,
							cy - 8,
							rl.WHITE,
						)
						break
					}
				}

			}
		}

		world_mp := rl.GetScreenToWorld2D(mouse_pos, camera)


		tile_x, tile_y := math.floor(world_mp.x / 16), math.floor(world_mp.y / 16)
		changed := false
		if tile_x_last != int(tile_x) {
			tile_x_last = int(tile_x)
			changed = true
		}
		if tile_y_last != int(tile_y) {
			tile_y_last = int(tile_y)
			changed = true
		}


		if place_mode == .Building {
			rl.DrawRectangleLines(i32(tile_x * 16), i32(tile_y * 16), 16, 16, rl.RED)

			building := building_registry[building_being_placed_idx]

			for tile in building.tiles {
				rl.DrawTextureRec(
					building.spritesheet_texture,
					rl.Rectangle{x = f32(tile.sprite_index * 16), y = 0, width = 16, height = 16},
					{(tile_x + f32(tile.x)) * 16.0, (tile_y + f32(tile.y)) * 16.0},
					rl.WHITE,
				)

			}
			if rl.IsMouseButtonPressed(.LEFT) {
				storage := make([dynamic]int)
				if building_registry[building_being_placed_idx].ident == "depot" {
					append(&storage, 0)
				}

				append(
					&placed_buildings,
					Placed_Building {
						x = int(tile_x),
						y = int(tile_y),
						building_idx = building_being_placed_idx,
						storage = storage,
					},
				)
			}

		} else if place_mode == .Belt {
			if belt_place_mode == .PendingA {
				rl.DrawRectangleLines(i32(tile_x * 16), i32(tile_y * 16), 16, 16, rl.DARKBLUE)

				if rl.IsMouseButtonPressed(.LEFT) {
					belt_a_pos.x = int(tile_x)
					belt_a_pos.y = int(tile_y)
					belt_place_mode = .PlacedA
				}

			} else if belt_place_mode == .PlacedA {

				if changed {
					if blip_sound_cooldown > 0.05 {
						rl.PlaySound(blipSound)
						blip_sound_cooldown = 0.0
					}

				}

				blip_sound_cooldown += delta

				rl.DrawRectangleLines(
					i32(belt_a_pos.x * 16),
					i32(belt_a_pos.y * 16),
					16,
					16,
					rl.MAGENTA,
				)

				length_to_mouse_tile := math.sqrt(
					math.pow(f32(belt_a_pos.x * 16) + 8.0 - (tile_x * 16.0 + 8.0), 2.0) +
					math.pow(f32(belt_a_pos.y * 16 + 8.0) - (tile_y * 16.0 + 8.0), 2.0),
				)
				belt_thickness: f32 = 12.0
				belt_center: rl.Vector2

				belt_center.x = (f32(belt_a_pos.x * 16.0 + 8.0) + (tile_x * 16.0 + 8.0)) / 2
				belt_center.y = (f32(belt_a_pos.y * 16.0 + 8.0) + (tile_y * 16.0 + 8.0)) / 2

				direc := math.to_degrees(
					math.atan2(
						f32(belt_a_pos.y * 16 + 8.0) - (tile_y * 16. + 8.0),
						f32(belt_a_pos.x * 16 + 8.0) - (tile_x * 16.0 + 8.0),
					),
				)

				rl.DrawRectanglePro(
					rl.Rectangle {
						belt_center.x,
						belt_center.y,
						length_to_mouse_tile,
						belt_thickness,
					},
					{length_to_mouse_tile / 2.0, belt_thickness / 2.0},
					direc,
					rl.GRAY,
				)
				rl.DrawCircleLines(
					i32(belt_a_pos.x * 16) + 8,
					i32(belt_a_pos.y * 16) + 8,
					7,
					rl.YELLOW,
				)

				if rl.IsMouseButtonPressed(.LEFT) {
					append(
						&placed_belts,
						Belt {
							point_a = rl.Vector2{f32(belt_a_pos.x), f32(belt_a_pos.y)},
							point_b = rl.Vector2{tile_x, tile_y},
							items_travelling = make([dynamic]Travelling_Item),
						},
					)
					belt_place_mode = .PendingA
				}

			}
		}

		rl.EndMode2D()

		if current_goal.is_none {
			rl.DrawText("No Goal Selected", 100, 100, 40, rl.WHITE)
		}
		else if current_goal.goal_type == .Chunk {
			text := fmt.tprintf("Current Goal:\nUnlock chunk %d, %d", current_goal.data.reward_chunk_x, current_goal.data.reward_chunk_y)
			cstring_text := strings.clone_to_cstring(text)
			rl.DrawText(cstring_text, 100, 100, 30, rl.WHITE)
			delete(cstring_text)
			

			
			for item_group, item_group_idx in current_goal.required_items.item_groups {
				reg_item_ptr: ^Registered_Item
				for &item in item_registry {
					if item.id == item_group.item_id {
						reg_item_ptr = &item
						break
					}
				}

				count_text := fmt.tprintf("%d", item_group.amount)
				cstring_count_text := strings.clone_to_cstring(count_text)

				
				rl.DrawTextureEx(reg_item_ptr.texture, {f32(80 + item_group_idx * 120), 180}, 0, 5.0, rl.WHITE)
				rl.DrawText(cstring_count_text, i32((80 + item_group_idx * 120) + 70), 250, 19, rl.WHITE)

				delete(cstring_count_text)
				
			}

			

			
		}
		else if current_goal.goal_type == .Unlock {
			rl.DrawText("Current Goal:\nUnlock ___", 100, 100, 30, rl.WHITE)
		}

		
			
	

		
		
		rl.EndDrawing()

		if rl.IsKeyPressed(rl.KeyboardKey.F4) {
			rl.ToggleFullscreen()
		}

		free_all(context.temp_allocator)
		
	}

}
