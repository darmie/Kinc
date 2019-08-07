


#import "Ar.h"
#import <MetalKit/MetalKit.h>

#include "pch.h"
#include <Kore/Ar/Session.h>
#include <Kore/Graphics4/Graphics.h>
#include <Kore/Graphics4/Texture.h>
#include <Kore/Graphics4/PipelineState.h>
#include <Kore/Graphics4/Shader.h>
#include <Kore/Graphics4/Vertexbuffer.h>
#include <Kore/Graphics4/VertexStructure.h>
#include <Kore/IO/FileReader.h>
#include <Kore/Math/Matrix.h>
#include <Kore/Math/Vector.h>



#include <stdio.h>

using namespace Kore;

namespace {
    static  Graphics4::Shader* getShader(const char* name, Kore::Graphics4::ShaderType type){
       FileReader shaderReader =  new FileReader(name);
       return new Graphics4::Shader(shaderReader.readAll(), shaderReader.size(), type);
    }

    #ifdef KORE_METAL
    MTLPixelFormat convert(kinc_image_format_t format) {
		switch (format) {
			case KINC_IMAGE_FORMAT_RGBA32:
				return MTLPixelFormatRGBA8Unorm;
			case KINC_IMAGE_FORMAT_GREY8:
				return MTLPixelFormatR8Unorm;
			case KINC_IMAGE_FORMAT_RGB24:
			case KINC_IMAGE_FORMAT_RGBA128:
			case KINC_IMAGE_FORMAT_RGBA64:
			case KINC_IMAGE_FORMAT_A32:
			case KINC_IMAGE_FORMAT_BGRA32:
			case KINC_IMAGE_FORMAT_A16:
				return MTLPixelFormatRGBA8Unorm;
		}
	}
    #endif
    #ifdef KORE_OPENGL
    static int convert(kinc_image_format_t format) {
        switch (format) {
        case KINC_IMAGE_FORMAT_BGRA32:
    #ifdef GL_BGRA
                return GL_BGRA;
    #else
                return GL_RGBA;
    #endif
        case KINC_IMAGE_FORMAT_RGBA32:
        case KINC_IMAGE_FORMAT_RGBA64:
        case KINC_IMAGE_FORMAT_RGBA128:
        default:
            return GL_RGBA;
        case KINC_IMAGE_FORMAT_RGB24:
            return GL_RGB;
        case KINC_IMAGE_FORMAT_A32:
        case KINC_IMAGE_FORMAT_A16:
        case KINC_IMAGE_FORMAT_GREY8:
            return GL_RED;
        }
    }
    #endif

    typedef struct {
        // Camera Uniforms
        Kore::mat4x4 projectionMatrix;
        Kore::mat4x4 viewMatrix;
        
        // Lighting Properties
        Kore::vec3 ambientLightColor;
        Kore::vec3 directionalLightDirection;
        Kore::vec3 directionalLightColor;
        float materialShininess;
    } SharedUniforms;

    typedef struct {
        Kore::mat4x4 modelMatrix;
    } InstanceUniforms;

}

// The max number of command buffers in flight
static const NSUInteger kMaxBuffersInFlight = 3;

// The max number anchors our uniform buffer will hold
static const NSUInteger kMaxAnchorInstanceCount = 64;

// The max number of command buffers in flight
static const NSUInteger kMaxBuffersInFlight = 3;


// The 256 byte aligned size of our uniform structures
static const size_t kAlignedSharedUniformsSize = (sizeof(SharedUniforms) & ~0xFF) + 0x100;
static const size_t kAlignedInstanceUniformsSize = ((sizeof(InstanceUniforms) * kMaxAnchorInstanceCount) & ~0xFF) + 0x100;


// Vertex data for an image plane
static const float kImagePlaneVertexData[16] = {
    -1.0, -1.0,  0.0, 1.0,
    1.0, -1.0,  1.0, 1.0,
    -1.0,  1.0,  0.0, 0.0,
    1.0,  1.0,  1.0, 0.0,
};

@implementation Ar {
    ARSession* _session;
    Kore::Ar::Session* kore_ar_session; 

    Graphics4::TextureUnit capturedImageTextureYRefID;
    Graphics4::TextureUnit capturedImageTextureCbCrRefID;
    Graphics4::Texture* capturedImageTextureYRef;
    Graphics4::Texture* capturedImageTextureCbCrRef;
    Graphics4::PipelineState* capturedImagePipelineState;
    Graphics4::PipelineState* anchorPipelineState;

    Graphics4::VertexStructure* cameraImage_structure;
    Graphics4::VertexStructure* anchor_structure;

    CVOpenGLESTextureCacheRef _coreVideoTextureCache;

    void *_sharedUniformBufferAddress;
    void *_anchorUniformBufferAddress;
    SharedUniforms *_sharedUniformBuffer;
    InstanceUniforms *_anchorUniformBuffer;
    uint8_t _uniformBufferIndex;
    NSUInteger _anchorInstanceCount;
    
    uint8_t _sharedUniformBufferOffset;
    uint8_t _anchorUniformBufferOffset;

    CGSize sceneSize;

    #ifdef KORE_OPENGL 
    EAGLContext* _context
    #endif
}

#ifdef KORE_OPENGL 
-(instanctype)initSessionWithGL:(ARSession *)session {
    self = [self initSession:session];
    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!_context || ![EAGLContext setCurrentContext:_context]){
            NSAssert(NO, @"Failed to init gl context !");
            return nil;
    }
    return self
}
#endif 

-(instanctype)initWithSession:(ARSession *)session {
    self = [super init];
    if (self) {
        _session = session;
        Kore::Ar::sessionStart = true;
        capturedImagePipelineState = new Graphics4::PipelineState();
        anchorPipelineState = new Graphics4::PipelineState();
    }

    #ifdef KORE_METAL
    // Create captured image texture cache
    CVMetalTextureCacheCreate(NULL, NULL, _device, NULL, &_capturedImageTextureCache);
    #endif

    #ifdef KORE_OPENGL
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, [self context], NULL, &_glTextureCache);
    NSAssert(err == 0, @"Failed to create CVOpenGLESTexture!");
    #endif

   

    // anchor pipeline setup
	anchor_structure = new Graphics4::VertexStructure();
	anchor_structure->add("position", Graphics4::VertexData::Float3VertexData);
    anchor_structure->add("texCoord", Graphics4::VertexData::Float2VertexData);
    anchor_structure->add("normal", Graphics4::VertexData::Float3VertexData);
    anchor_structure->add("color", Graphics4::VertexData::ColorVertexData);

    anchorPipelineState->inputLayout[0] = anchor_structure;
    anchorPipelineState->inputLayout[1] = nullptr;

    Graphics4::Shader* anchor_vertexshader = getShader("ar-anchor.vert", Graphics4::ShaderType::VertexShader);
    Graphics4::Shader* anchor_fragmentshader = getShader("ar-anchor.frag", Graphics4::ShaderType::FragmentShader);
    anchorPipelineState->vertexShader = anchor_vertexshader;
	anchorPipelineState->fragmentShader = anchor_fragmentshader;
    anchorPipelineState->compile();

    // camera image pipeline setup
	cameraImage_structure = new Graphics4::VertexStructure();
	cameraImage_structure->add("position", Graphics4::VertexData::Float3VertexData);
    cameraImage_structure->add("texCoord", Graphics4::VertexData::Float2VertexData);

    capturedImagePipelineState->inputLayout[0] = cameraImage_structure;
    capturedImagePipelineState->inputLayout[1] = nullptr;

    Graphics4::Shader* camera_vertexshader = getShader("ar-camera.vert", Graphics4::ShaderType::VertexShader);
    Graphics4::Shader* camera_fragmentshader = getShader("ar-camera.frag", Graphics4::ShaderType::FragmentShader);
    capturedImagePipelineState->vertexShader = camera_vertexshader;
	capturedImagePipelineState->fragmentShader = camera_fragmentshader;
    capturedImagePipelineState->compile();

    // ConstantLocation getConstantLocation(const char* name);

    capturedImageTextureYRefID = capturedImagePipelineState->getTextureUnit("capturedImageTextureY");
    capturedImageTextureCbCrRefID = capturedImagePipelineState->getTextureUnit("capturedImageTextureCbCr");

    Graphics4::VertexBuffer* s_positions = new Graphics4::VertexBuffer(4, cameraImage_structure);
    float* v = s_positions->lock();
    v[0] = -1;
    v[1] = -1;
    v[2] = 0;
    v[3] = 1;
    v[4] = 1;
    v[5] = -1;
    v[6] = 0;
    v[7] = 1;
    v[8] = -1;
    v[9] = 1;
    v[10] = 0;
    v[11] = 1;
    v[12] = 1;
    v[13] = 1;
    v[14] = 0;
    v[15] = 1;
	s_positions->unlock();

    
    Graphics4::VertexBuffer* s_texCoords = new Graphics4::VertexBuffer(2, cameraImage_structure);
    float *v = s_texCoords->lock();
    v[0] = 0;
    v[1] = 1;
    v[2] = 1;
    v[3] = 1;
    v[4] = 0;
    v[5] = 0;
    v[6] = 1;
    v[7] = 0;
	s_texCoords->unlock();

    return self;
}


-(void)drawCameraFrame:(ARFrame *)frame{
    if (!frame) {
        return;
    }

    // create texture
    CVPixelBufferRef pixelBuffer = frame.capturedImage;
    if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
        return;
    }

    [self createTextureFromPixelBuffer:pixelBuffer
                         texture:&capturedImageTextureYRef
                            pixeFormat:KINC_IMAGE_FORMAT_GREY8
                            planeIndex:0];
    [self createTextureFromPixelBuffer:pixelBuffer
                         texture:&capturedImageTextureCbCrRef
                            pixeFormat:KINC_IMAGE_FORMAT_GREY8
                            planeIndex:1];

    Graphics4::setPipeline(capturedImagePipelineState);
    Graphics4::setVertexBuffer(*s_positions);
    Graphics4::setVertexBuffer(*s_texCoords);
    Graphics4::setTexture(capturedImageTextureYRefID, capturedImageTextureYRef);
    Graphics4::setTexture(capturedImageTextureCbCrRefID, capturedImageTextureCbCrRef);
}

-(void) createTextureFromPixelBuffer:(CVPixelBufferRef)pixelBuffer texture:(Graphics4::Texture*)texture pixeFormat:(int)pixelFormat planeIndex:(NSUInteger)planeIndex {
   
    const size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex);
    const size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex);
    
    texture = new Texture(width, height, Kore::Graphics1::Image::Format::Grey8);
    
    #ifdef KORE_OPENGL
    CVOpenGLESTextureRef outputTexture = nil
    CVReturn status = CVOpenGLESTextureCacheCreateTextureFromImage(NULL,
                                                                   _glTextureCache,
                                                                   pixelBuffer,
                                                                   NULL,
                                                                   GL_TEXTURE_2D,
                                                                   convert(pixeFormat),
                                                                   (GLsizei)width,
                                                                   (GLsizei)height,
                                                                   convert(pixeFormat),
                                                                   GL_UNSIGNED_BYTE,
                                                                   planeIndex,
                                                                   &outputTexture);
    NSAssert(status == kCVReturnSuccess, @"failed to create texture cache"); 
    GLuint _t = CVOpenGLESTextureGetName(outputTexture);
    texture->texture.impl.texture = _t
    glBindTexture(GL_TEXTURE_2D, _t);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);                                                 
    #endif  

    #ifdef KORE_METAL
    CVMetalTextureRef outputTexture = nil;
    CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, _capturedImageTextureCache, pixelBuffer, NULL, convert(pixelFormat), width, height, planeIndex, &outputTexture);
    if (status != kCVReturnSuccess) {
        CVBufferRelease(outputTexture);
        outputTexture = nil;
    }
    texture->texture.impl._tex = outputTexture
    #endif
}


- (void)_updateBufferStates {
    // Update the location(s) to which we'll write to in our dynamically changing Metal buffers for
    //   the current frame (i.e. update our slot in the ring buffer used for the current frame)
    _uniformBufferIndex = (_uniformBufferIndex + 1) % kMaxBuffersInFlight;
    
    _sharedUniformBufferOffset = kAlignedSharedUniformsSize * _uniformBufferIndex;
    _anchorUniformBufferOffset = kAlignedInstanceUniformsSize * _uniformBufferIndex;
    
    _sharedUniformBufferAddress = ((uint8_t*)_sharedUniformBuffer) + _sharedUniformBufferOffset;
    _anchorUniformBufferAddress = ((uint8_t*)_anchorUniformBuffer) + _anchorUniformBufferOffset;
}


- (void)_updateSharedUniformsWithFrame:(ARFrame *)frame {
    // Update the shared uniforms of the frame
    SharedUniforms *uniforms = (SharedUniforms *)_sharedUniformBufferAddress;
    Kore::mat4x4 CAM = Kore::mat4x4::Identity();
    matrix_float4x4 _c = matrix_invert(frame.camera.transform)
    for(int i = 0; i < sizeof(_c.columns); i++){
        CAM[0][i] = _c.columns[i].x;
        CAM[1][i] = _c.columns[i].y;
        CAM[2][i] = _c.columns[i].z;
    }
    
    uniforms->viewMatrix = CAM;

    Kore::mat4x4 PM = Kore::mat4x4::Identity();
    matrix_float4x4 _p = [frame.camera projectionMatrixForOrientation:UIInterfaceOrientationLandscapeRight
                                                                 viewportSize:sceneSize
                                                                        zNear:0.001
                                                                         zFar:1000];
    for(int i = 0; i < sizeof(_p.columns); i++){
        PM[0][i] = _p.columns[i].x;
        PM[1][i] = _p.columns[i].y;
        PM[2][i] = _p.columns[i].z;
    }
    uniforms->projectionMatrix = PM;
    
    // Set up lighting for the scene using the ambient intensity if provided
    float ambientIntensity = 1.0;
    
    if (frame.lightEstimate) {
        ambientIntensity = frame.lightEstimate.ambientIntensity / 1000;
    }
    
    Kore::vec3 ambientLightColor = new Vector(0.5, 0.5, 0.5);
    uniforms->ambientLightColor = ambientLightColor * ambientIntensity;
    
    Kore::vec3 directionalLightDirection = new Vector(0.0, 0.0, -1.0);
    directionalLightDirection = directionalLightDirection.normalize();
    uniforms->directionalLightDirection = directionalLightDirection;
    
    Kore::vec3 directionalLightColor =  new Vector(0.6, 0.6, 0.6);
    uniforms->directionalLightColor = directionalLightColor * ambientIntensity;
    
    uniforms->materialShininess = 30;
}


- (void)_updateAnchorsWithFrame:(ARFrame *)frame {
    // Update the anchor uniform buffer with transforms of the current frame's anchors
    NSInteger anchorInstanceCount = MIN(frame.anchors.count, kMaxAnchorInstanceCount);
    
    NSInteger anchorOffset = 0;
    if (anchorInstanceCount == kMaxAnchorInstanceCount) {
        anchorOffset = MAX(frame.anchors.count - kMaxAnchorInstanceCount, 0);
    }
    
    for (NSInteger index = 0; index < anchorInstanceCount; index++) {
        InstanceUniforms *anchorUniforms = ((InstanceUniforms *)_anchorUniformBufferAddress) + index;
        ARAnchor *anchor = frame.anchors[index + anchorOffset];

        
        // Flip Z axis to convert geometry from right handed to left handed
        Kore::mat4x4 coordinateSpaceTransform =  Kore::mat4x4::RotationZ(-1.0);
        // coordinateSpaceTransform.columns[2].z = -1.0;
        Kore::mat4x4 ANC = Kore::mat4x4::Identity();
        matrix_float4x4 _anc = anchor.transform;
        for(int i = 0; i < sizeof(_anc.columns); i++){
            ANC[0][i] = _anc.columns[i].x;
            ANC[1][i] = _anc.columns[i].y;
            ANC[2][i] = _anc.columns[i].z;
        }
        
        anchorUniforms->modelMatrix = ANC *= coordinateSpaceTransform;
    }
    
    _anchorInstanceCount = anchorInstanceCount;
}

-(void)update:(CGSize)viewSize {
    ARFrame *frame = _sesstion.currentFrame;
    if (!frame) {
        return;
    }

    sceneSize = viewSize;

    [self _updateBufferStates];
    [self _updateARState:frame];
}

- (void)_updateARState:(ARFrame *)frame {
    [self _updateSharedUniformsWithFrame:frame];
    [self _updateAnchorsWithFrame:frame];
    [self drawCameraFrame:frame];
}

- (void)_drawAnchorGeometry
{
    // kinc_g4_set_pipeline(&anchorPipelineState);
    // kinc_g4_texture_unit_t position = kinc_g4_pipeline_get_constant_location(&anchorPipelineState, "position");
    // kinc_g4_texture_unit_t texCoord = kinc_g4_pipeline_get_constant_location(&anchorPipelineState, "texCoord");
    // kinc_g4_texture_unit_t normal = kinc_g4_pipeline_get_constant_location(&anchorPipelineState, "normal");
    // kinc_g4_texture_unit_t color = kinc_g4_pipeline_get_constant_location(&anchorPipelineState, "color");

   
    // for(int i = 0; i < _anchorInstanceCount; i++){
    //     kinc_g4_constant_location_t modelMatrix = kinc_g4_pipeline_get_constant_location(&anchorPipelineState, "modelMatrix");
    //     kinc_matrix4x4_t am4;
    //     float *am = (float *)&_anchorUniformBuffer[i].modelMatrix;
    //     std::copy(am, sizeof(am), am4.m);
    //     kinc_g4_set_matrix4(modelMatrix, &am4);
    //     SharedUniforms *uniforms = (SharedUniforms *)_sharedUniformBufferAddress;

    //     kinc_g4_constant_location_t projectionMatrix = kinc_g4_pipeline_get_constant_location(&anchorPipelineState, "projectionMatrix");
    //     kinc_matrix4x4_t pm4;
    //     float* pm = (float *)&uniforms->projectionMatrix;
    //     std::copy(pm, sizeof(am), pm4.m);
    //     kinc_g4_set_matrix4(projectionMatrix, &pm4);

    //     kinc_g4_constant_location_t viewMatrix = kinc_g4_pipeline_get_constant_location(&anchorPipelineState, "viewMatrix");
    //     kinc_matrix4x4_t vm4;
    //     float* vm = (float *)&uniforms->viewMatrix;
    //     std::copy(vm, sizeof(vm), vm4.m);
    //     kinc_g4_set_matrix4(viewMatrix, &vm4);

    //     kinc_g4_constant_location_t ambientLightColor = kinc_g4_pipeline_get_constant_location(&anchorPipelineState, "ambientLightColor");
    //     kinc_matrix3x3_t ambi3;
    //     float* ambi = (float *)&uniforms->ambientLightColor;
    //     std::copy(ambi, sizeof(ambi), ambi3.m);
    //     kinc_g4_set_matrix3(ambientLightColor, &ambi3);


    //     kinc_g4_constant_location_t directionalLightDirection = kinc_g4_pipeline_get_constant_location(&anchorPipelineState, "directionalLightDirection");
    //     kinc_matrix3x3_t dld3;
    //     float* dld= (float *)&uniforms->directionalLightDirection;
    //     std::copy(dld, sizeof(dld), dld3.m);
    //     kinc_g4_set_matrix3(directionalLightDirection, &dld3);

    //     kinc_g4_constant_location_t directionalLightColor = kinc_g4_pipeline_get_constant_location(&anchorPipelineState, "directionalLightColor");
    //     kinc_matrix3x3_t dlc3;
    //     float* dld= (float *)&uniforms->directionalLightColor;
    //     std::copy(dlc, sizeof(dlc), dlc3.m);
    //     kinc_g4_set_matrix3(directionalLightColor, &dlc3);

    //     kinc_g4_constant_location_t materialShininess = kinc_g4_pipeline_get_constant_location(&anchorPipelineState, "materialShininess");
    //     kinc_g4_set_float(materialShininess, uniforms->materialShininess);

    //     [self renderModels];
    // }
}




-(void)dealloc {
}

