#include <stdio.h>


// Generic utils

typedef float3 pixel;

void check_result(cudaError_t value) {
	cudaError_t status = value;
	if (status != cudaSuccess) {
		printf("Error %s at line %d in file %s\n",
			cudaGetErrorString(status), __LINE__, __FILE__);
		// exit(1);
	}
}

__device__ float3 operator+(const float3 &a, const float3 &b) {
	return make_float3(a.x + b.x,a.y + b.y,a.z + b.z);
}

__device__ float3 operator*(const float3 &a, const float &b) {
	return make_float3(a.x * b, a.y * b, a.z * b);
}

__device__ float length(const float3 &vec) {
	return sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z);
}

__device__ float3 normalize(const float3 vec) {
	float inverted_len = 1.0f / length(vec);
	return vec * inverted_len;
}


// Raymarcher

typedef struct {
	float3 o;
	float3 d;
} ray;

__device__ ray get_ray(const float& u, const float& v) {
	ray r;
	r.o = make_float3(-5.0, 0.0, 0.0);
	r.d = normalize(make_float3(1.0, u, v));
	return r;
}

__device__ float mandelbulb_de(float3 pos) {
	// pos = fmod(fabs(pos), 4.0) - 2.0;
	float3 z = pos;
	float dr = 1.0;
	float r = 0.0;
	int Iterations = 4;
	float Bailout = 4.0;
	float Power = 8.0;
	for(int i = 0; i < Iterations; i++) {
		r = length(z);
		if (r > Bailout) break;

		// convert to polar coordinates
		float theta = acos(z.z / r);
		float phi = atan2(z.y, z.x);
		dr = powf(r, Power - 1.0) * Power * dr + 1.0;

		// scale and rotate the point
		float zr = pow(r, Power);
		theta = theta * Power;
		phi = phi * Power;

		// convert back to cartesian coordinates
		z = make_float3(sin(theta) * cos(phi),
				sin(phi) * sin(theta), cos(theta)) * zr;
		z = z + pos;
		//z += pos * cos(time * 2.0);
	}
	return 0.5 * log(r) * r / dr;
}

__device__ float march(ray r) {
	float total_dist = 0.0;
	int max_ray_steps = 64;
	float min_distance = 0.002;

	int steps;
	for (steps = 0; steps < max_ray_steps; ++steps) {
		float3 p = r.o + r.d * total_dist;
		float distance = mandelbulb_de(p);
		total_dist += distance;
		if (distance < min_distance) break;
	}
	return 1.0 - (float) steps / (float) max_ray_steps;
}


// Main kernel

__global__ void d_main(
	pixel* screen_buffer,
	const size_t &width,
	const size_t &height
) {
	size_t x = (blockIdx.x * blockDim.x) + threadIdx.x;
	size_t y = (blockIdx.y * blockDim.y) + threadIdx.y;
	
	if((x < width && y < height) && false) {
		float min_w_h = (float) min(width, height);

		float ar = (float) width / (float) height;
		float u = (float) x / min_w_h - ar * 0.5f;
		float v = (float) y / min_w_h - 0.5f;

		ray r = get_ray(u, v);
		float c = march(r) * 255.0f;
		float3 color = make_float3(c, c, c);
	}
	screen_buffer[y * width + x] = make_float3(255.0f, 255.0f, 255.0f);
}

int main(int argc, char** argv) {
	printf("Mandelbulb\n");
	
	size_t width = 32;
	size_t height = 32;
	size_t num_pixels = width * height;

	size_t group_width = 1;
	size_t group_height = 1;

	// Setup buffers
	pixel* h_screen_buff;
	pixel* d_screen_buff;
	check_result(cudaMallocHost(&h_screen_buff, num_pixels * sizeof(pixel)));
	check_result(cudaMalloc(&d_screen_buff, num_pixels * sizeof(pixel)));

	dim3 block_dim(width / group_width, height / group_height);
	dim3 group_dim(group_width, group_height);

	// Execute on devicie
	printf("Starting kernel execution...\n");
	d_main<<<block_dim, group_dim>>>(d_screen_buff, width, height);
	printf("Kernel execution ended.\n");

	printf("Reading screan buffer from device...\n");
	check_result(cudaMemcpy(h_screen_buff, d_screen_buff, num_pixels * sizeof(pixel), cudaMemcpyDeviceToHost));
	printf("Done.\n");

	for(size_t y = 0;y < height;y++) {
		for(size_t x = 0;x < width;x++) {
			printf("%i ", (int) h_screen_buff[y * width + x].x);
		}
		printf("\n");
	}

	cudaFreeHost(h_screen_buff);
	cudaFree(d_screen_buff);

	return 0;
}

