# GifControl

Things that need to be adjusted in the XCode workspace:
1. Set `ENABLE BITCODE` to No.


The name is a lie, for now, because I can't figure out SwiftUI. Current functionality: say "stop" to make the current text turn to "stop", and say "go" to make the current text turn to "go." This project demonstrates the integration of a model trained on the Google Speech commands dataset, according to the paper `DEEP RESIDUAL LEARNING FOR SMALL-FOOTPRINT KEYWORD SPOTTING` (https://arxiv.org/pdf/1710.10361.pdf) and the following Github repo: https://github.com/castorini/honk. 

I used the `RES15_NARROW` architecture with a few modifications. The most notable modification was actually just mean-scaling the MFCC features before feeding them to the model. This speeds convergence up significantly, by maybe 20 epochs, and improves accuracy slightly.

The performance of the model on my iPhone XR is not that great. It seems to be quite accurate, but the CPU usage is ~100%, even for such simple functionality. I found that pretty much all of the CPU usage is from evaluating the model, and almost none from the preprocessing steps (STFFT + MFCC using the Accelerate framework). 

I have two future goals for the project. On the modelling side, I would like to get a workable model using some less energy intensive architectures like ResNet8 or ResNetTC. On the iOS side, I would like to get a GIF to play and stop using voice. This would be a stepping stone to other more complicated voice apps. 

The reason why I am taking a break from this is mostly because reading Apple documentation and dealing with XCode issues have crushed a part of my soul. The sad part is that Swift is actually a great programming language, and I would totally use it more if I didn't feel Apple shoving its hand up my ass everytime I try to debug my code.

