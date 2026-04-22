#include <FastLED.h>
#include <PacketSerial.h>

PacketSerial_<COBS, 0, 512> myPacketSerial;

#define NLEDS     198
#define NSUNS_MAX 198
#define DATA_PIN  10
#define CLOCK_PIN 11
#define BAUDRATE  115200
#define NO_POS    0xFF   // sentinel: sun not yet placed

uint8_t azimuths[NSUNS_MAX];
CRGB leds[NLEDS];

void setup() {
  for (int i = 0; i < NSUNS_MAX; i++) azimuths[i] = NO_POS;
  FastLED.addLeds<DOTSTAR, DATA_PIN, CLOCK_PIN, BGR>(leds, NLEDS);
  FastLED.clear();
  FastLED.show();
  myPacketSerial.begin(BAUDRATE);
  myPacketSerial.setPacketHandler(&onPacketReceived);
}

void loop() {
  myPacketSerial.update();
}

void onPacketReceived(const uint8_t* buff, size_t nb) {
  if (nb == 0 || nb % 3 != 0) return;           // malformed
  const size_t nsuns = nb / 3;

  // Validate every entry before mutating any state.
  for (size_t s = 0; s < nsuns; s++) {
    uint8_t id      = buff[3*s + 0];
    uint8_t azimuth = buff[3*s + 1];
    if (id >= NSUNS_MAX || azimuth >= NLEDS) return;
  }

  // Pass 1: clear all old positions.
  for (size_t s = 0; s < nsuns; s++) {
    uint8_t id = buff[3*s + 0];
    if (azimuths[id] != NO_POS) leds[azimuths[id]] = CRGB::Black;
  }

  // Pass 2: write new positions and update state.
  for (size_t s = 0; s < nsuns; s++) {
    uint8_t id      = buff[3*s + 0];
    uint8_t azimuth = buff[3*s + 1];
    uint8_t green   = buff[3*s + 2];
    leds[azimuth] = CRGB(0, green, 0);
    azimuths[id]  = azimuth;
  }

  FastLED.show();
}

