package main

miner_tile_id_to_item_id :: proc(tile_id: u8) -> int {
	if !(tile_id == 0 || tile_id == 1) {
		if tile_id == 2 {
			return 0
		}
		if tile_id == 3 {
			return 1
		}
	}
	return -1
}

