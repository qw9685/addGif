//
//  ViewController.m
//  本地视频-雪花,爆破效果
//
//  Created by cc on 2020/1/17.
//  Copyright © 2020 mac. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface ViewController ()

@end

@implementation ViewController

-(void)viewDidLoad{
    
    NSArray<NSURL*>* videos = @[
        [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"1.mp4" ofType:nil]],
    ];
    
    NSArray<NSURL*>* gifPaths = @[
        [[NSBundle mainBundle] URLForResource:@"雪花" withExtension:@"gif"],
        [[NSBundle mainBundle] URLForResource:@"烟花" withExtension:@"gif"],

    ];
    
    NSString* outPath = [NSString stringWithFormat:@"%@/cache.mp4",[self dirDoc]];
    [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    
    [self addVideos:videos gifPaths:gifPaths outPath:outPath];
}

- (void)addVideos:(NSArray<NSURL*>*)videos gifPaths:(NSArray<NSURL*>*)gifPaths outPath:(NSString*)outPath{
    
    AVMutableComposition *mix = [AVMutableComposition composition];
    
    //用来管理视频中的所有视频轨道
    AVMutableVideoComposition *mainCompositionInst = [AVMutableVideoComposition videoComposition];
    //输出对象 会影响分辨率
    AVAssetExportSession* exporter = [[AVAssetExportSession alloc] initWithAsset:mix presetName:AVAssetExportPresetHighestQuality];
    
    NSMutableArray<AVAsset*>* assets = [NSMutableArray array];
    NSMutableArray<AVMutableCompositionTrack*>* videoCompositionTracks = [NSMutableArray array];
    NSMutableArray<AVAssetTrack*>* tracks = [NSMutableArray array];
    
    //资源插入起始时间点
    __block CMTime atTime = kCMTimeZero;
    __block CMTime maxDuration = kCMTimeZero;
    
    //加载音视频轨道
    [videos enumerateObjectsUsingBlock:^(NSURL* obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        AVAsset* asset = [AVAsset assetWithURL:obj];
        AVAssetTrack* videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
        AVAssetTrack* audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
        
        //视频轨道容器
        AVMutableCompositionTrack* videoCompositionTrack = [mix addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        
        AVMutableCompositionTrack* audioCompositionTrack = [mix addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        
        [videoCompositionTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoTrack.asset.duration) ofTrack:videoTrack atTime:atTime error:nil];
        [audioCompositionTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoTrack.asset.duration) ofTrack:audioTrack atTime:atTime error:nil];
        

        [tracks addObject:videoTrack];
        [assets addObject:asset];
        
        [videoCompositionTracks addObject:videoCompositionTrack];
        
        atTime = CMTimeAdd(atTime, videoTrack.asset.duration);
        maxDuration = CMTimeAdd(maxDuration, videoTrack.asset.duration);
    }];
    
    //获取分辨率
    CGSize renderSize = [self getNaturalSize:tracks[0]];
    //设置分辨率
    mainCompositionInst.renderSize = renderSize;
    //可加载多个轨道
    mainCompositionInst.instructions = @[[self getCompositionInstructions:videoCompositionTracks tracks:tracks assets:assets maxDuration:maxDuration naturalSize:renderSize]];
    //设置视频帧率
    mainCompositionInst.frameDuration = videoCompositionTracks[0].minFrameDuration;
    mainCompositionInst.renderScale = 1.0;
    
    
    //exporter设置
    exporter.outputURL = [NSURL fileURLWithPath:outPath];
    exporter.outputFileType = AVFileTypeQuickTimeMovie;
    exporter.shouldOptimizeForNetworkUse = YES;//适合网络传输
    
    [self addAnimationLayerFromGif:gifPaths videoSize:renderSize resultBlock:^(AVVideoCompositionCoreAnimationTool *animationTool) {
                
        mainCompositionInst.animationTool = animationTool;
        exporter.videoComposition = mainCompositionInst;
        
        [exporter exportAsynchronouslyWithCompletionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (exporter.status == AVAssetExportSessionStatusCompleted) {
                    NSLog(@"成功");
                    [self playVideoWithUrl:[NSURL fileURLWithPath:outPath]];
                }else{
                    NSLog(@"失败--%@",exporter.error);
                }
            });
        }];
    }];
}

//获取animationTool
- (void)addAnimationLayerFromGif:(NSArray<NSURL*>*)gifPaths videoSize:(CGSize)videoSize resultBlock:(void(^)(AVVideoCompositionCoreAnimationTool* animationTool))resultBlock{
    
    CALayer *parentLayer = [CALayer layer];
    parentLayer.frame = CGRectMake(0, 0, videoSize.width, videoSize.height);
    parentLayer.geometryFlipped = true;
    
    CALayer *videoLayer = [CALayer layer];
    videoLayer.frame = CGRectMake(0, 0, videoSize.width, videoSize.height);
    
    [parentLayer addSublayer:videoLayer];
    
    [gifPaths enumerateObjectsUsingBlock:^(NSURL * _Nonnull gifPath, NSUInteger idx, BOOL * _Nonnull stop) {

        [self addGifAnimationFromGifPath:gifPath resultBlock:^(CAKeyframeAnimation *animation) {

            CALayer* gifLayer = [CALayer layer];
            gifLayer.frame = CGRectMake(0, 0, videoSize.width, videoSize.height);
            [gifLayer addAnimation:animation forKey:@"gif"];
            [parentLayer addSublayer:gifLayer];
            
            if (idx == gifPaths.count - 1) {
                //最后
                AVVideoCompositionCoreAnimationTool* animationTool = [AVVideoCompositionCoreAnimationTool videoCompositionCoreAnimationToolWithPostProcessingAsVideoLayer:videoLayer inLayer:parentLayer];
                resultBlock(animationTool);
            }
        }];
    }];
}

//获取动画
- (void)addGifAnimationFromGifPath:(NSURL*)gifPath resultBlock:(void(^)(CAKeyframeAnimation* animation))resultBlock{
    
    [self getImagesWithGif:gifPath resultBlock:^(NSArray<UIImage *> *images, CGFloat totalTime, NSArray* delayTimes) {

        NSMutableArray *times = [NSMutableArray arrayWithCapacity:3];
        CGFloat currentTime = 0;
        NSInteger count = delayTimes.count;
        for (int i = 0; i < count; ++i) {
            [times addObject:[NSNumber numberWithFloat:(currentTime / totalTime)]];
            currentTime += [[delayTimes objectAtIndex:i] floatValue];
        }

        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"contents"];
        animation.keyTimes = times;//帧时间
        animation.values = images;//总图片
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        animation.duration = totalTime;
        animation.repeatCount = HUGE_VALF;
        animation.beginTime = AVCoreAnimationBeginTimeAtZero;
        animation.removedOnCompletion = NO;
        
        resultBlock(animation);
    }];
}

//从gif提取帧图片信息
-(void)getImagesWithGif:(NSURL *)gifPath resultBlock:(void(^)(NSArray<UIImage*>* images,CGFloat totalTime,NSArray* delayTimes))resultBlock{
        
    CGImageSourceRef gifSource = CGImageSourceCreateWithURL((CFURLRef)gifPath, NULL);
    size_t gifCount = CGImageSourceGetCount(gifSource);
    
    NSMutableArray *times = [NSMutableArray array];
    NSMutableArray *images = [NSMutableArray array];
    NSMutableArray *delayTimes = [NSMutableArray array];

    CGFloat totalTime = 0.0;
    CGFloat currentTime = 0.0;
    for (size_t i = 0; i< gifCount; i++) {
        
        CGImageRef imageRef = CGImageSourceCreateImageAtIndex(gifSource, i, NULL);
        [images addObject:(__bridge id _Nonnull)(imageRef)];
        
        //获取到的gif中帧信息
        NSDictionary *dict = (NSDictionary*)CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(gifSource, i, NULL));
        NSDictionary *gifDict = [dict valueForKey:(NSString*)kCGImagePropertyGIFDictionary];
        
        //持续时间
        CGFloat time = [[gifDict valueForKey:(NSString*)kCGImagePropertyGIFUnclampedDelayTime] floatValue];
        
        [delayTimes addObject:[NSNumber numberWithFloat:time]];
        //总时间
        totalTime = totalTime + time;
    }
    //图片占据时间点
    [delayTimes enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSNumber* number = [NSNumber numberWithFloat:[obj floatValue] + currentTime];
        [times addObject:number];
    }];
    
    resultBlock(images,totalTime,times);
}
- (AVMutableVideoCompositionInstruction*)getCompositionInstructions:(NSArray<AVMutableCompositionTrack*>*)compositionTracks tracks:(NSArray<AVAssetTrack*>*)tracks assets:(NSArray<AVAsset*>*)assets maxDuration:(CMTime)maxDuration naturalSize:(CGSize)naturalSize{
    
    //资源动画范围
    __block CMTime atTime = kCMTimeZero;
    
    NSMutableArray* layerInstructions = [NSMutableArray array];
    
    //视频轨道中的一个视频，可以缩放、旋转等
    AVMutableVideoCompositionInstruction *mainInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    mainInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, maxDuration);
    
    [compositionTracks enumerateObjectsUsingBlock:^(AVMutableCompositionTrack * _Nonnull compositionTrack, NSUInteger idx, BOOL * _Nonnull stop) {
        AVAssetTrack *assetTrack = tracks[idx];
        AVAsset *asset = assets[idx];
        
        AVMutableVideoCompositionLayerInstruction *layerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:compositionTrack];
        
        //设置旋转角度
        CGAffineTransform transfrom = [self getTransfromFromTrack:assetTrack naturalSize:naturalSize];
        [layerInstruction setTransform:transfrom atTime:kCMTimeZero];
        
        //设置透明
        atTime = CMTimeAdd(atTime, asset.duration);
        [layerInstruction setOpacity:0.0 atTime:atTime];
        
        [layerInstructions addObject:layerInstruction];
    }];
    
    mainInstruction.layerInstructions = layerInstructions;
    
    return mainInstruction;
}

- (CGAffineTransform)getTransfromFromTrack:(AVAssetTrack*)track naturalSize:(CGSize)naturalSize{
    
    UIImageOrientation assetOrientation = UIImageOrientationUp;
    BOOL isPortrait = NO;
    CGAffineTransform transfrom = track.preferredTransform;
    
    if(transfrom.a == 0 && transfrom.b == 1.0 && transfrom.c == -1.0 && transfrom.d == 0) {
        assetOrientation = UIImageOrientationRight;
        isPortrait = YES;
    }
    if(transfrom.a == 0 && transfrom.b == -1.0 && transfrom.c == 1.0 && transfrom.d == 0) {
        assetOrientation = UIImageOrientationLeft;
        isPortrait = YES;
    }
    if(transfrom.a == 1.0 && transfrom.b == 0 && transfrom.c == 0 && transfrom.d == 1.0) {
        assetOrientation = UIImageOrientationUp;
    }
    if(transfrom.a == -1.0 && transfrom.b == 0 && transfrom.c == 0 && transfrom.d == -1.0) {
        assetOrientation = UIImageOrientationDown;
    }
    
    CGFloat assetScaleToFitRatio = naturalSize.width / track.naturalSize.width;
    
    if(isPortrait) {
        assetScaleToFitRatio = naturalSize.width / track.naturalSize.height;
        CGAffineTransform assetScaleFactor = CGAffineTransformMakeScale(assetScaleToFitRatio,assetScaleToFitRatio);
        transfrom = CGAffineTransformConcat(track.preferredTransform, assetScaleFactor);
    }else{
        CGAffineTransform assetScaleFactor = CGAffineTransformMakeScale(assetScaleToFitRatio,assetScaleToFitRatio);
        transfrom = CGAffineTransformConcat(CGAffineTransformConcat(track.preferredTransform, assetScaleFactor),CGAffineTransformMakeTranslation(0, naturalSize.width/2));
    }
    return transfrom;
}


- (CGSize)getNaturalSize:(AVAssetTrack*)track{
    
    UIImageOrientation assetOrientation  = UIImageOrientationUp;
    BOOL isPortrait  = NO;
    CGAffineTransform videoTransform = track.preferredTransform;
    
    if (videoTransform.a == 0 && videoTransform.b == 1.0 && videoTransform.c == -1.0 && videoTransform.d == 0) {
        assetOrientation = UIImageOrientationRight;
        isPortrait = YES;
    }
    if (videoTransform.a == 0 && videoTransform.b == -1.0 && videoTransform.c == 1.0 && videoTransform.d == 0) {
        assetOrientation =  UIImageOrientationLeft;
        isPortrait = YES;
    }
    if (videoTransform.a == 1.0 && videoTransform.b == 0 && videoTransform.c == 0 && videoTransform.d == 1.0) {
        assetOrientation =  UIImageOrientationUp;
    }
    if (videoTransform.a == -1.0 && videoTransform.b == 0 && videoTransform.c == 0 && videoTransform.d == -1.0) {
        assetOrientation = UIImageOrientationDown;
    }
    
    //根据视频中的naturalSize及获取到的视频旋转角度是否是竖屏来决定输出的视频图层的横竖屏
    CGSize naturalSize;
    if(assetOrientation){
        naturalSize = CGSizeMake(track.naturalSize.height, track.naturalSize.width);
    } else {
        naturalSize = track.naturalSize;
    }
    return naturalSize;
}

-(void)playVideoWithUrl:(NSURL *)url{
    AVPlayerViewController *playerViewController = [[AVPlayerViewController alloc]init];
    playerViewController.player = [[AVPlayer alloc]initWithURL:url];
    playerViewController.view.frame = self.view.frame;
    [playerViewController.player play];
    [self presentViewController:playerViewController animated:YES completion:nil];
}

//获取Documents目录
-(NSString *)dirDoc{
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}


@end
