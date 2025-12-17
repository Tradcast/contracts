import { ethers } from 'ethers';

function isNonIntegerStr(input: any) {
  return typeof input === 'string' && /^[0-9\/]+$/.test(input) === false;
}
function isBigNumber(value: any) {
  return !!(value && (value._isBigNumber || (value.type == 'BigNumber' && value.hex)));
}
function isObject(value: any) {
  const type = typeof value;
  if (value == null) {
    return false;
  }
  if (type === 'object') {
    if (value instanceof Date) {
      return false;
    }
    return true;
  }
  return false;
}

function mapRecursive(input: any, modifierFn: Function, parent?: any, parentKey?: string) {
  if (isObject(input)) {
    let rt = modifierFn.call(parent, parentKey, input);
    if (rt === input) {
      rt = {
        ...input,
      };
    }
    if (isObject(rt)) {
      for (let key in rt) {
        if ({}.hasOwnProperty.call(rt, key)) {
          rt[key] = mapRecursive(rt[key], modifierFn, rt, key);
        }
      }
    }
    return rt;
  } else {
    return modifierFn.call(parent, parentKey, input);
  }
}

function modifier(this: any, key: string, value: any) {
  if (Array.isArray(value)) {
    if (Object.keys(value).find(isNonIntegerStr)) {
      const filtered = Object.keys(value)
        .filter(isNonIntegerStr)
        .reduce((obj: Record<string, any>, k: string) => {
          // @ts-ignore
          obj[k] = value[k];
          return obj;
        }, {});
      return filtered;
    }
  }
  if (
    (key.toLowerCase().endsWith('time') || key.toLowerCase().endsWith('date')) &&
    typeof value === 'number'
  ) {
    if (value < 1919431723) {
      return new Date(value * 1000).toJSON();
    } else {
      return new Date(value).toJSON();
    }
  }
  if (typeof value === 'bigint') {
    return 'bigint(' + value.toString() + ')';
  } else if (isBigNumber(value)) {
    if (value.gte('1000000000000')) {
      return 'BigNumber(' + value.toString() + ') ETH=' + ethers.utils.formatEther(value);
    }
    return 'BigNumber(' + value.toString() + ')';
  } else {
    return value;
  }
}

export function toReadableJson(input: any) {
  return JSON.stringify(mapRecursive(input, modifier), null, 2);
}
