"""Maintainer tool: cut a small, fixed evaluation subset out of COCO val2017.

Only needed to regenerate coco_val2017_subset.json; evaluators use that file.

    python make_subset.py path/to/instances_val2017.json --n 500

Selection: landscape 640x480 images (the 4:3 aspect of the phone camera's
ResolutionPreset.low frame, so no cropping is needed), sampled with a fixed
seed. COCO annotations are CC BY 4.0 (https://cocodataset.org/#termsofuse).
"""
import argparse
import json
import random


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("instances_json")
    ap.add_argument("--n", type=int, default=500)
    ap.add_argument("--seed", type=int, default=2026)
    ap.add_argument("--out", default="coco_val2017_subset.json")
    args = ap.parse_args()

    coco = json.load(open(args.instances_json, encoding="utf-8"))
    imgs = sorted((i for i in coco["images"] if i["width"] == 640 and i["height"] == 480),
                  key=lambda i: i["id"])
    random.Random(args.seed).shuffle(imgs)
    chosen = sorted(imgs[: args.n], key=lambda i: i["id"])
    ids = {i["id"] for i in chosen}
    anns = [a for a in coco["annotations"] if a["image_id"] in ids]
    for a in anns:
        a.pop("segmentation", None)  # not needed for box AP; keeps the file small
    subset = {
        "info": {
            "description": f"DO Robotics eval subset: {len(chosen)} COCO val2017 images (640x480), seed {args.seed}",
            "source": "https://cocodataset.org  (annotations CC BY 4.0; images keep their Flickr licenses and are downloaded, not redistributed)",
        },
        "licenses": coco["licenses"],
        "categories": coco["categories"],
        "images": [{k: i[k] for k in ("id", "file_name", "width", "height", "coco_url", "license")} for i in chosen],
        "annotations": anns,
    }
    json.dump(subset, open(args.out, "w", encoding="utf-8"), separators=(",", ":"))
    print(f"{len(chosen)} images, {len(anns)} annotations -> {args.out}")


if __name__ == "__main__":
    main()
