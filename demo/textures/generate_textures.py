#!/usr/bin/env python3
"""Generates the demo's tileable ground textures (no downloads needed).

Run from this folder:  python3 generate_textures.py   (needs numpy and Pillow)

Everything repeats seamlessly. The ground uses just two textures, packed so the
shader reads each pixel's grass and dirt in one go (fewer texture reads is the
main GPU saving on the headset):

  ground_mix.png      R = grass shade, G = dirt shade, B = grass blade streaks
                      (greyscale values; the shader turns them into colours)
  ground_normals.png  R,G = grass surface detail, B,A = dirt surface detail
                      (the x and y of each normal; z is worked out in the shader)

Both cover the same patch of ground, 1 / 0.42 = 2.38 m across.
"""
import numpy as np
from PIL import Image

RNG = np.random.default_rng(11)
N = 512          # ground_mix size
NN = 256         # ground_normals size (detail is only drawn up close)


def periodic_noise(n, power, stretch=(1.0, 1.0), rng=RNG):
    """Seamless noise: random phases with a 1/f^power spectrum (wraps perfectly)."""
    fx = np.fft.fftfreq(n)[None, :] * stretch[0]
    fy = np.fft.fftfreq(n)[:, None] * stretch[1]
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1.0
    spectrum = (rng.normal(size=(n, n)) + 1j * rng.normal(size=(n, n))) / f ** power
    spectrum[0, 0] = 0
    x = np.real(np.fft.ifft2(spectrum))
    return normalize(x)


def normalize(x):
    x = x - x.min()
    return x / x.max()


def cells(n, count, rng=RNG):
    """Seamless cellular noise: distance to the nearest of count x count jittered
    points (0 at a point), like pebbles packed in dirt."""
    pts = (np.stack(np.meshgrid(np.arange(count), np.arange(count), indexing="ij"), -1) + rng.random((count, count, 2))) / count
    y, x = np.mgrid[0:n, 0:n] / n
    best = np.full((n, n), 9.0)
    cx = np.floor(x * count).astype(int)
    cy = np.floor(y * count).astype(int)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ix = (cx + dx) % count
            iy = (cy + dy) % count
            p = pts[ix, iy]
            ddx = (x - p[..., 0] + 0.5) % 1.0 - 0.5
            ddy = (y - p[..., 1] + 0.5) % 1.0 - 0.5
            best = np.minimum(best, np.hypot(ddx, ddy))
    return normalize(best)


def normal_xy(height, strength):
    """x and y of a tangent-space normal map from a height map (wraps), 0..1."""
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * strength
    length = np.sqrt(dx ** 2 + dy ** 2 + 1.0)
    return -dx / length * 0.5 + 0.5, dy / length * 0.5 + 0.5


def down(img, n):
    """Box-filters a square array to n x n."""
    k = img.shape[0] // n
    return img.reshape(n, k, n, k).mean(axis=(1, 3))


def to8(x):
    return np.clip(np.round(x * 255), 0, 255).astype(np.uint8)


def main():
    # Grass: soft clumps with a little finer variation.
    grass = normalize(0.7 * periodic_noise(N, 1.25) + 0.3 * periodic_noise(N, 0.7))
    blades = periodic_noise(N, 0.55, stretch=(4.0, 0.6))      # streaky, like blades
    # Dirt: packed pebbles plus soft variation.
    pebbles = cells(N, 40)
    dirt = normalize(0.75 * pebbles + 0.25 * periodic_noise(N, 1.0))

    Image.fromarray(np.dstack([to8(grass), to8(dirt), to8(blades)]), "RGB").save("ground_mix.png")
    print("wrote ground_mix.png")

    grass_h = down(0.6 * periodic_noise(N, 0.9) + 0.4 * blades, NN)
    dirt_h = down(1.0 - pebbles, NN)                            # pebbles stand up
    gx, gy = normal_xy(grass_h, 5.0)
    dx, dy = normal_xy(dirt_h, 7.0)
    Image.fromarray(np.dstack([to8(gx), to8(gy), to8(dx), to8(dy)]), "RGBA").save("ground_normals.png")
    print("wrote ground_normals.png")


if __name__ == "__main__":
    main()
