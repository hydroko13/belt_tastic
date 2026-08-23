package main

import rl "vendor:raylib"
import "core:os"
import "core:strings"
import "core:encoding/json"


Registered_Item :: struct {
	name: string,
	texture: rl.Texture,
	id: int
}

Item_Data :: struct {
	id: int
}

load_items :: proc(item_registry: ^[dynamic]Registered_Item) -> bool {
	cwd, err := os.get_working_directory(context.allocator)
	if err != os.General_Error.None {
		return false
	}


	defer delete(cwd)

	items_dir, join_err := os.join_path({cwd, "res", "items"}, context.allocator)

	if join_err != .None {
		return false
	}

	defer delete(items_dir)

	items_dir_handle, open_err := os.open(items_dir)

	if open_err != os.General_Error.None {
		return false
	}

	defer os.close(items_dir_handle)

	file_infos, read_err := os.read_dir(items_dir_handle, -1, context.allocator)

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

			if is_json { 	// read item json file
				item_file_path, join_err := os.join_path(
					{cwd, "res", "items", filename},
					context.allocator,
				)

				if join_err != .None {
					return false
				}

				concat_result, _ := strings.concatenate({file_name_no_ext, ".png"})


				item_image_Path, join_err_img := os.join_path(
					{cwd, "res", "items", concat_result},
					context.allocator,
				)

				delete(concat_result)

				file_contents, file_err := os.read_entire_file(
					item_file_path,
					context.allocator,
				)

				if file_err == os.General_Error.None {
					data: Item_Data

					json_parse_err := json.unmarshal(transmute([]u8)file_contents, &data)

					if json_parse_err == nil {

						new_item: Registered_Item

						new_item.name = file_name_no_ext
						new_item.id = data.id
						cstr := strings.clone_to_cstring(item_image_Path)
						delete(cstr)
						new_item.texture = rl.LoadTexture(cstr)
						delete(item_image_Path)

						
						append(item_registry, new_item)


					}


				}


				delete(file_contents)


			}

			delete(parts)


		}
	}


	return true

}
