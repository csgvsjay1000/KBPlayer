//
//  ViewController.m
//  KBPlayer
//
//  Created by chengshenggen on 5/18/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "ViewController.h"
#import "KBPlayerEnumHeaders.h"

//#import "PlayerController.h"
//#import "KBPlayerController2_0.h"
//#import "KBPlayerController3_0.h"
//#import "KBPlayerController4_0.h"
//#import "KBPlayerController5_0.h"  // 直播封装在Controller里，功能比较完整  版本1.0.0
//#import "KBPlayerController6_0.h"
//#import "KBPlayerController7_0.h"    //直播封装到uiview里面，使外面controller使用方便  版本2.0.0
#import "KBPlayerController8_0.h"
//#import "KBPlayerController9_0.h"  //硬解


const NSString *keyVideoType = @"keyVideoType";
const NSString *keyVideoTypeValue = @"keyVideoTypeValue";
const NSString *keyVideoUrl = @"keyVideoUrl";
const NSString *keyNetType = @"keyNetType";

@interface ViewController ()<UITableViewDataSource,UITableViewDelegate>

@property(nonatomic,strong)UITableView *tableView;

@property(nonatomic,strong)NSMutableArray *array;

@end

@implementation ViewController

#pragma mark - life cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self.view addSubview:self.tableView];
    [self.tableView reloadData];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - UITableViewDataSource,UITableViewDelegate
-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"UITableViewCell" forIndexPath:indexPath];
    cell.textLabel.text = [self.array[indexPath.row] objectForKey:keyVideoTypeValue];
    
    return cell;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return self.array.count;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    KBPlayerController8_0 *vc = [[KBPlayerController8_0 alloc] init];
    vc.videoDictionary = self.array[indexPath.row];
    [self presentViewController:vc animated:NO completion:nil];
    
}

#pragma mark - setters and getters

-(UITableView *)tableView{
    if (_tableView == nil) {
        CGRect frame = CGRectMake(0, 20, self.view.bounds.size.width, self.view.bounds.size.height-20);
        _tableView = [[UITableView alloc] initWithFrame:frame style:UITableViewStylePlain];
        _tableView.dataSource = self;
        _tableView.delegate = self;
        [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"UITableViewCell"];
    }
    return _tableView;
}

-(NSMutableArray *)array{
    if (_array == nil) {
        _array = [[NSMutableArray alloc] init];
        NSString *path = [[NSBundle mainBundle] pathForResource:@"cuc_ieschool" ofType:@"flv"];

        [_array addObject:@{
                            keyVideoType:[NSNumber numberWithInteger:KBPlayerVideoTypeNormal],
                            keyVideoTypeValue:@"本地普通视屏",
                            keyVideoUrl:path,
                            keyNetType:[NSNumber numberWithInteger:KBPlayerNetTypeLocal]}];
        
        //rtmp://live.hkstv.hk.lxdns.com/live/hks  香港卫视直播流
        //rtmp://0fwc91.live1-rtmp.z1.pili.qiniucdn.com/shutong/test1
        [_array addObject:@{
                            keyVideoType:[NSNumber numberWithInteger:KBPlayerVideoTypeNormal],
                            keyVideoTypeValue:@"香港卫视直播",
                            keyVideoUrl:@"rtmp://0fwc91.live1-rtmp.z1.pili.qiniucdn.com/shutong/test1",
                            keyNetType:[NSNumber numberWithInteger:KBPlayerNetTypeLive]}];
        [_array addObject:@{
                            keyVideoType:[NSNumber numberWithInteger:KBPlayerVideoTypePanorama],
                            keyVideoTypeValue:@"全景直播",
                            keyVideoUrl:@"rtmp://0fwc91.live1-rtmp.z1.pili.qiniucdn.com/shutong/test1",
//                            keyVideoUrl:@"rtmp://0fwc91.live1-rtmp.z1.pili.qiniucdn.com/shutong/test1",
                            keyNetType:[NSNumber numberWithInteger:KBPlayerNetTypeLive]}];
//        NSString *path_panormal = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"mp4"];
//
//        [_array addObject:@{
//                            keyVideoType:[NSNumber numberWithInteger:KBPlayerVideoTypePanorama],
//                            keyVideoTypeValue:@"本地全景视频",
//                            keyVideoUrl:path_panormal,
//                            keyNetType:[NSNumber numberWithInteger:KBPlayerNetTypeLocal]}];
////        NSString *path_panormal_updown = [[NSBundle mainBundle] pathForResource:@"Galaxy11VR" ofType:@"mp4"];
//
//        [_array addObject:@{
//                            keyVideoType:[NSNumber numberWithInteger:KBPlayerVideoTypePanoramaUpAndDown],
//                            keyVideoTypeValue:@"本地上下全景",
////                            keyVideoUrl:path_panormal_updown,
//                            keyNetType:[NSNumber numberWithInteger:KBPlayerNetTypeLocal]}];
        
        
    }
    return _array;
}

@end
