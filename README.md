# homepage
A minimal web server using SwiftNIO for my homepage. It might be running at [boris.diamonds](http://boris.diamonds).

## Building
The project uses Swift Package manager.
Make sure at least Swift 5.0 is installed, either by installing Xcode on a Mac, or on Linux follow the instructions at
[swift.org](https://swift.org/download/#releases).

After cloning the project run
`swift package update`

To create an Xcode project to work in Xcode run
`swift package generate-xcodeproj`

## Running
Run a command like

`swift run -c release homepage -n localhost --c ~/Contents`

For all options run swift run -c release homepage --help.

