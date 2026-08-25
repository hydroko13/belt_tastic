package main

smelter_recipe_input_output :: proc(recipe_id: int) -> (input_item: int, output_item: int) {
	switch recipe_id {
	case 0:
		return 0, 2
	}

	return -1, -1
}