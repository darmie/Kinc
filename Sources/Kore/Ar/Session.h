
#include <Kore/Graphics4/Graphics.h>
#include <Kore/Graphics4/Texture.h>
#include <Kore/Math/Matrix.h>

namespace Kore {

	namespace Ar {
		struct LightData {
			float intensity;
			float colorTemperature;
		};

		struct Session {
			float capturedImageTimeInterval;
			LightData *lightData;
			Kore::Graphics4::VertexBuffer imagePlaneVertexBuffer;
			Kore::Graphics4::Texture *cameraImageTextureY;
            Kore::Graphics4::Texture *cameraImageTextureCbCr;
			Kore::Graphics4::VertexBuffer sharedBuffer;
			Kore::Graphics4::VertexBuffer anchorBuffer;

			Kore::mat4x4 cameraProjectionMatrix;
			Kore::mat4x4 cameraViewMatrix;
			Kore::mat4x4 cameraViewPort;
		};

        static bool sessionStart;
        static Session* session;
	}
}