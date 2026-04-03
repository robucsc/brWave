# brWave

brWave is a macOS patch librarian, translator, and interchange hub for the PPG/Wave ecosystem, including the Behringer Wave, PPG Wave, and Waldorf Wave 3.V-style formats.

Built with SwiftUI, brWave is aimed at making patch data easier to read, organize, inspect, convert, and move across related hardware and software instruments.

## What It Does

- Imports and organizes patch libraries in a native macOS app
- Reads Behringer Wave SysEx (`.syx`) patch data
- Imports Waldorf PPG Wave 3.V / 2.V bank files (`.fxb`)
- Provides patch editing, library browsing, and bank management tools
- Includes a Galaxy view for visual patch exploration by similarity
- Supports current MIDI communication for Behringer Wave workflows
- Lays the groundwork for broader PPG MIDI integration

## Project Direction

brWave is not intended to be limited to a single synth. The long-term goal is to act as a central conduit between PPG/Wave-family instruments and formats, allowing patch data to move more freely across:

- Behringer Wave
- PPG Wave hardware generations
- Waldorf PPG Wave 3.V and related plugin-era formats
- Future MIDI-based PPG workflows

## Tech

- Swift
- SwiftUI
- Core Data
- CoreMIDI
- Xcode project for macOS

## Status

This repository currently focuses on the application source and project files. Large reference assets, plugin bundles, and research archives are kept out of the GitHub repo.

## Repo Description

Short GitHub description suggestion:

`macOS patch librarian and interchange hub for the PPG/Wave ecosystem`
