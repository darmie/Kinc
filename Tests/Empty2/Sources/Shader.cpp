#include "pch.h"

#include <kinc/display.h>
#include <kinc/graphics4/graphics.h>
#include <kinc/graphics4/indexbuffer.h>
#include <kinc/graphics4/pipeline.h>
#include <kinc/graphics4/shader.h>
#include <kinc/graphics4/vertexbuffer.h>
#include <kinc/graphics4/vertexstructure.h>
#include <kinc/input/mouse.h>
#include <kinc/input/mouse.h>
#include <kinc/io/filereader.h>
#include <kinc/system.h>
#include <kinc/audio2/audio.h>
#include <kinc/log.h>

#include <limits>
#include <stdio.h>
#include <stdlib.h>

kinc_g4_shader_t vertexshader;
kinc_g4_shader_t fragmentshader;
kinc_g4_pipeline_t pipeline;
kinc_g4_vertex_buffer_t vertices;
kinc_g4_index_buffer_t indices;

int window;

void Say(){

}

void update() {
	printf("update\n");

	Say();

	kinc_g4_begin(window);
	kinc_g4_clear(KINC_G4_CLEAR_COLOR, 0, KINC_G4_CLEAR_DEPTH, KINC_G4_CLEAR_STENCIL);
	kinc_g4_set_pipeline(&pipeline);
	kinc_g4_set_vertex_buffer(&vertices);
	kinc_g4_set_index_buffer(&indices);
	kinc_g4_draw_indexed_vertices();

	kinc_g4_end(window);
	kinc_g4_swap_buffers();
}

int kickstart(int argc, char **argv) {
	window = kinc_init("Shader", 1024, 768, NULL, NULL);
	kinc_set_update_callback(update);

	kinc_file_reader_t vs;
	kinc_file_reader_t fs;

	if (kinc_file_reader_open(&vs, "shader.vert", KINC_FILE_TYPE_ASSET)) {
		void *data;

		kinc_file_reader_seek(&vs, 0);
		free(data);
		int size = (int)kinc_file_reader_size(&vs);
		data = malloc(size);
		kinc_file_reader_read(&vs, data, size);
		kinc_g4_shader_init(&vertexshader, data, size, KINC_G4_SHADER_TYPE_VERTEX);
		kinc_file_reader_close(&vs);
	}

	if (kinc_file_reader_open(&fs, "shader.frag", KINC_FILE_TYPE_ASSET)) {
		void *data;
		free(data);
		int size = (int)kinc_file_reader_size(&fs);
		data = malloc(size);
		kinc_file_reader_read(&fs, data, size);
		kinc_g4_shader_init(&fragmentshader, data, size, KINC_G4_SHADER_TYPE_FRAGMENT);
		kinc_file_reader_close(&fs);
	}

	kinc_g4_vertex_structure structure;

	kinc_g4_vertex_structure_init(&structure);

	kinc_g4_vertex_structure_add(&structure, "pos", KINC_G4_VERTEX_DATA_FLOAT3);

	kinc_g4_pipeline_init(&pipeline);

	pipeline.input_layout[0] = &structure;
	pipeline.input_layout[1] = NULL;
	pipeline.vertex_shader = &vertexshader;
	pipeline.fragment_shader = &fragmentshader;
	kinc_g4_pipeline_compile(&pipeline);

	kinc_g4_vertex_buffer_init(&vertices, 3, &structure, KINC_G4_USAGE_STATIC, 0);
	float *v = kinc_g4_vertex_buffer_lock(&vertices, 0, 3);
	v[0] = -1;
	v[1] = -1;
	v[2] = 0.5;
	v[3] = 1;
	v[4] = -1;
	v[5] = 0.5;
	v[6] = -1;
	v[7] = 1;
	v[8] = 0.5;
	kinc_g4_vertex_buffer_unlock(&vertices, 3);

	kinc_g4_index_buffer_init(&indices, 3);
	int *i = kinc_g4_index_buffer_lock(&indices);
	i[0] = 0;
	i[1] = 1;
	i[2] = 2;
	kinc_g4_index_buffer_unlock(&indices);

	kinc_start();

	return 0;
}