#ifndef MNISTREAD_H
#define MNISTREAD_H

#include <iostream>
#include <string>

typedef unsigned char uchar;

int reverseInt(int i);

// read images from file 
uchar* readMNISTImages(std::string &path, int &num_images, int &img_size);

// read labels from file
uchar* readMNISTLabels(std::string &path, int &num_labels);

#endif