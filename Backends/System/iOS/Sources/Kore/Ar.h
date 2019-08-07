


#import <Foundation/Foundation.h>
#import <ARKit/ARKit.h>
#import <CoreVideo/CoreVideo.h>
#ifdef KORE_OPENGL
#import <GLKit/GLKit.h>
#endif

#ifdef KORE_METAL
@interface Ar : NSObject <ARSessionDelegate, MTKViewDelegate>
    CVMetalTextureCacheRef _capturedImageTextureCache;

    - (instancetype)initWithSession:(ARSession *)session;
    - (void)update:(CGSize)viewSize;
@end
#endif

#ifdef KORE_OPENGL
@interface Ar : NSObject <ARSessionDelegate, GLKViewDelegate>
    CVOpenGLESTextureCacheRef _glTextureCache;
    @property (nonatomic, readonly, strong) EAGLContext *context;

    - (instancetype)initWithSession:(ARSession *)session;
    - (void)update:(CGSize)viewSize;
@end
#endif


