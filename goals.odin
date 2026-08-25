package main

NoGoal :: struct {
	
}

LandGoal :: struct {
	chunk_x: int,
	chunk_y: int
}



Goal :: union {
	NoGoal,
	LandGoal
	
}