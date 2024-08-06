import os
import shutil

import numpy as np
import pachyderm_sdk
import pandas as pd
import torch
from pachyderm_sdk.api.pfs import File, FileType
from PIL import Image
from skimage import io
from sklearn.model_selection import train_test_split
from torch.utils.data import DataLoader, Dataset
from torchvision import transforms


class MRI_Dataset(Dataset):
    def __init__(self, path_df, data_dir, transform=None):
        self.path_df = path_df
        self.transform = transform
        self.data_dir = data_dir
        
    def __len__(self):
        return self.path_df.shape[0]
    
    def __getitem__(self, idx):
        
        base_path = os.path.join(self.data_dir, self.path_df.iloc[idx]['directory'].strip("/"))
        img_path = os.path.join(base_path, self.path_df.iloc[idx]['images'])
        mask_path = os.path.join(base_path, self.path_df.iloc[idx]['masks'])
        
        image = Image.open(img_path)
        mask = Image.open(mask_path)
        
        sample = (image, mask)
        
        if self.transform:
            sample = self.transform(sample)
            
        return sample
    
class PairedToTensor():
    def __call__(self, sample):
        img, mask = sample
        img = np.array(img)
        mask = np.expand_dims(mask, -1)
        img = np.moveaxis(img, -1, 0)
        mask = np.moveaxis(mask, -1, 0)
        img, mask = torch.FloatTensor(img), torch.FloatTensor(mask)
        img = img/255
        mask = mask/255
        return img, mask
    
def get_train_val_datasets(download_dir, data_dir, seed, validation_ratio=0.2):
    
    dirs, images, masks = [], [], []


    full_dir = "/"
    full_dir = os.path.join(full_dir, download_dir.strip("/"), data_dir.strip("/"))
    
    print("full_dir = " + full_dir)

    for root, folders, files in  os.walk(full_dir):
        for file in files:
            if 'mask' in file:
                dirs.append(root.replace(full_dir, ''))
                masks.append(file)
                images.append(file.replace("_mask", ""))

    
    PathDF = pd.DataFrame({'directory': dirs,
                          'images': images,
                          'masks': masks})

    
    train_df, valid_df = train_test_split(PathDF, random_state=seed,
                                     test_size = validation_ratio)
    

    
    train_data = MRI_Dataset(train_df, full_dir, transform=PairedToTensor())
    valid_data = MRI_Dataset(valid_df, full_dir, transform=PairedToTensor())
    
    return train_data, valid_data



# ======================================================================================================================



def safe_open_wb(path):
    ''' Open "path" for writing, creating any parent directories as needed.
    '''
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return open(path, 'wb')


def download_pach_repo(
    pachyderm_host,
    pachyderm_port,
    repo,
    branch,
    root,
    token,
    fileset_id,
    datum_id
):
    print(f"Starting to download dataset: {repo}@{branch} --> {root}")
    datum_path = f"/pfs/{datum_id}"

    if not os.path.exists(root):
        os.makedirs(root)

    if not os.path.exists(f"{root}/pfs/{datum_id}"):
        os.makedirs(f"{root}/pfs/{datum_id}")
    
    client = pachyderm_sdk.Client(
        host=pachyderm_host, port=pachyderm_port, auth_token=token
    )
    
    
    client.storage.assemble_fileset(
        fileset_id,
        path=datum_path,
        destination=root,
    )
    print(f"List of files in the dataset: {[(os.path.join(root, file), file) for file in os.listdir(root)]}")
    return [(os.path.join(root, file), file) for file in os.listdir(root)]


# ========================================================================================================