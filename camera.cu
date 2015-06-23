#include "optix.h"
#include <optix_world.h>
#include "datadef.h"

using namespace optix;

rtBuffer<source_point,1>            positions_buffer;
rtBuffer<unsigned,1>                rxn_buffer;
rtBuffer<unsigned,1>                remap_buffer;
rtBuffer<unsigned,1>                done_buffer;
rtBuffer<unsigned,1>                cellnum_buffer;
rtBuffer<unsigned,1>                matnum_buffer;
rtDeclareVariable(rtObject,      top_object, , );
rtDeclareVariable(uint, launch_index_in, rtLaunchIndex, );
rtDeclareVariable(uint, launch_dim,   rtLaunchDim, );
rtDeclareVariable(unsigned,  outer_cell, , );
rtDeclareVariable(unsigned,  trace_type, , );
rtDeclareVariable(unsigned,  boundary_condition, , );

RT_PROGRAM void camera()
{
	//skip done particles

	//remap if 2
	unsigned launch_index;
	if(trace_type==2){
		launch_index=remap_buffer[launch_index_in];
		if(rxn_buffer[launch_index_in]>900){return;}
	}
	else{
		launch_index = launch_index_in;
	}

	// declare important stuff
	int                 sense = 0;
	float               epsilon=1.0e-4; 	
	intersection_point  payload;
	
	// init payload flags
	payload.sense = 0;
	payload.cell  = 999999;
	payload.mat   = 999999;
	payload.cell  = 999999;
	payload.fiss  = 0;
	
	// init ray
	float3 ray_direction  = make_float3(positions_buffer[launch_index].xhat, positions_buffer[launch_index].yhat, positions_buffer[launch_index].zhat);
	float3 ray_origin     = make_float3(positions_buffer[launch_index].x,    positions_buffer[launch_index].y,    positions_buffer[launch_index].z);
	optix::Ray ray        = optix::make_Ray( ray_origin, ray_direction, 0, epsilon, RT_DEFAULT_MAX );

	// first trace to find closest hit, set norm/distance, set bc flag
	rtTrace(top_object, ray, payload);
	//if(launch_index_in==98427){rtPrintf("sense %d playload.sense %d playload.cell %u xyz %6.4f %6.4f %6.4f\n",sense,payload.sense,payload.cell,payload.x,payload.y,payload.z);}
	if(trace_type==2){
		positions_buffer[launch_index].surf_dist = payload.surf_dist; 
		positions_buffer[launch_index].norm[0]   = payload.norm[0];
		positions_buffer[launch_index].norm[1]   = payload.norm[1];
		positions_buffer[launch_index].norm[2]   = payload.norm[2];
		// write bc flag if first hit is outer cell
		if(payload.cell == outer_cell){
			positions_buffer[launch_index].enforce_BC = boundary_condition;
		}
		else{
			positions_buffer[launch_index].enforce_BC = 0;
		}
	}

	// re-init sense, payload, ray
	sense = 0;
	payload.sense = 0;
	payload.cell  = 999999;
	payload.mat   = 999999;
	payload.cell  = 999999;
	payload.fiss  = 0;
	ray_direction = make_float3(0,0,-1);
	ray = optix::make_Ray( ray_origin, ray_direction, 0, epsilon, RT_DEFAULT_MAX );
	

	// then find entering cell, use downward z to make problems with high x-y density faster
	rtTrace(top_object, ray, payload);
	sense = payload.sense;
	while( (sense>=0) & (outer_cell!=payload.cell)){
		ray_origin = make_float3(payload.x+epsilon*ray_direction.x,payload.y+epsilon*ray_direction.y,payload.z+epsilon*ray_direction.z);
		ray = optix::make_Ray( ray_origin, ray_direction, 0, epsilon, RT_DEFAULT_MAX );
		rtTrace(top_object, ray, payload);
		sense = sense + payload.sense;
		//if(launch_index_in==98427){rtPrintf("sense %d \n",sense);}
	}
	//if(payload.cell == outer_cell){rtPrintf("outer cell sense %d\n",sense);}

	// write cell/material numbers to buffer
	if(trace_type == 2){ //write material to buffer normally, write surface distance
		matnum_buffer[launch_index] 				= payload.mat;
		cellnum_buffer[launch_index] 				= payload.cell;
	}
	else if(trace_type == 3){  //write fissile flag if fissile query
		matnum_buffer[launch_index] 				= payload.fiss;
		cellnum_buffer[launch_index] 				= payload.cell;
		rxn_buffer[launch_index_in] 				= 818;
	}

}

RT_PROGRAM void exception()
{
	const unsigned int code = rtGetExceptionCode();
	rtPrintf( "Caught exception 0x%X at launch index (%d)\n", code, launch_index_in);
	rtPrintExceptionDetails();
}
