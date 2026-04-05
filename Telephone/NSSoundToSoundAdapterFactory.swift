//
//  NSSoundToSoundAdapterFactory.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

final class NSSoundToSoundAdapterFactory {
    func makeSound(configuration: SoundConfiguration, target: SoundEventTarget) throws -> Sound {
        if let sound = sound(named: configuration.name) {
            update(sound, withDeviceID: configuration.deviceUID)
            return NSSoundToSoundAdapter(sound: sound, target: target)
        } else {
            throw TelephoneError.soundCreationError
        }
    }
}

private func sound(named name: String) -> NSSound? {
    if let systemSound = NSSound(named: name) {
        return systemSound
    }

    let soundFileExtensions = ["aiff", "aif", "aifc", "mp3", "wav", "sd2", "au", "snd", "m4a", "m4p"]

    if let bundledSound = soundFromBundle(named: name, extensions: soundFileExtensions) {
        return bundledSound
    }

    for libraryPath in NSSearchPathForDirectoriesInDomains(.libraryDirectory, .allDomainsMask, true) {
        let soundsDirectory = (libraryPath as NSString).appendingPathComponent("Sounds")
        if let fileSound = soundFromDirectory(path: soundsDirectory, named: name, extensions: soundFileExtensions) {
            return fileSound
        }
    }

    return nil
}

private func soundFromBundle(named name: String, extensions: [String]) -> NSSound? {
    for fileExtension in extensions {
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Sounds"),
           let sound = NSSound(contentsOf: url, byReference: false) {
            return sound
        }
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
           let sound = NSSound(contentsOf: url, byReference: false) {
            return sound
        }
    }
    return nil
}

private func soundFromDirectory(path: String, named name: String, extensions: [String]) -> NSSound? {
    let fileManager = FileManager.default
    for fileExtension in extensions {
        let fileName = "\(name).\(fileExtension)"
        let filePath = (path as NSString).appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: filePath),
           let sound = NSSound(contentsOfFile: filePath, byReference: false) {
            return sound
        }
    }
    return nil
}

private func update(_ sound: NSSound, withDeviceID deviceID: String) {
    if !deviceID.isEmpty {
        sound.playbackDeviceIdentifier = deviceID
    }
}
