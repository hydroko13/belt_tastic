package main

import "core:math/rand"

Goal_Type :: enum {
	Chunk,
	Unlock
}

Goal :: struct {
	data: GoalData,
	required_items: ItemCollection,
	is_none: bool,
	goal_type: Goal_Type
	
}


empty_goal :: proc() -> Goal {
	return Goal {
		required_items = create_empty_item_collection(),
		is_none = true,
		goal_type = Goal_Type.Unlock // if is_none is true then this is ignored
	}
}

delete_goal :: proc(goal: ^Goal) {
	delete_item_collection(&goal.required_items)
}

set_goal_to_none :: proc(goal: ^Goal) {
	goal.is_none = true
}

set_goal_to_chunk :: proc(goal: ^Goal, chunk_x, chunk_y: int) {
	goal.goal_type = .Chunk
	goal.is_none = false
	item_collection_clear(&goal.required_items)
	loot_table := [?]int{
		0,
	}
	
	for _ in 0..<rand.int_range(2, 5) {
		item_collection_add(&goal.required_items, rand.choice(loot_table[:]), rand.int_range(8, 20))
	}

	goal.data.reward_chunk_x = chunk_x
	goal.data.reward_chunk_y = chunk_y
	
}

set_goal_to_unlock :: proc(goal: ^Goal) {
	goal.goal_type = .Unlock
}

GoalData :: struct {
	reward_chunk_x: int,
	reward_chunk_y: int
}

