# FF7 Rebirth on AMD BC-250 (CachyOS)

A guide for getting **Final Fantasy VII Rebirth** fully functional on the **AMD BC-250** APU running **CachyOS** using a custom patched Mesa/RADV Vulkan driver.

> **Credits:** Special thanks to **Vogar345** for the original fix and tweaks!

---

## ⚠️ Important
**Make sure to set the Steam Launch Options** at the bottom of this guide after completing the build steps, or the game will not use the modified driver.

---

## 🛠️ Step-by-Step Setup

### 1. Clone the Repository
Clone the toolkit repository (or navigate to it if you already downloaded it):

```bash
git clone [https://github.com/lonewolf0622/FF7BC250.git](https://github.com/lonewolf0622/FF7BC250.git) ~/bc250-toolkit
cd ~/bc250-toolkit