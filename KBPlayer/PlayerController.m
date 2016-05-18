//
//  PlayerController.m
//  KBPlayer
//
//  Created by chengshenggen on 5/18/16.
//  Copyright © 2016 Gan Tian. All rights reserved.
//

#import "PlayerController.h"
#import "FFmpegHeader.h"

@interface PlayerController ()

@end

@implementation PlayerController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor whiteColor];
    printf("------\n%s\n----------",avcodec_configuration());
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
