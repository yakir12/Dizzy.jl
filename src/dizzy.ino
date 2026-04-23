#include <FastLED.h>
#include <PacketSerial.h>

PacketSerial_<COBS, 0, 512> myPacketSerial;  // adjust size to your worst-case encoded frame

#define NLEDS 198
#define DATA_PIN 11
#define CLOCK_PIN 13
#define BAUDRATE 115200

CRGB leds[NLEDS];

void setup() {
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
  if (nb % 2 != 0) return;
  const size_t nsuns = nb / 2;

  // Validate every entry before mutating any state.
  for (size_t s = 0; s < nsuns; s++) {
    uint8_t azimuth = buff[2 * s + 0];
    if (azimuth >= NLEDS) return;
  }

  FastLED.clear();

  for (size_t s = 0; s < nsuns; s++) {
    uint8_t azimuth = buff[2 * s + 0];
    uint8_t green = buff[2 * s + 1];
    leds[azimuth] = CRGB(0, green, 0);
  }

  FastLED.show();
}
